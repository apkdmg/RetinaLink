#include <metal_stdlib>
using namespace metal;

struct Params { uint width, height, columns, force; };
void putbits(thread uint4 &out, thread uint &pos, uint value, uint count) {
    for (uint j=0;j<count;j++,pos++) out[pos/32] |= ((value>>j)&1u) << (pos%32);
}
constant uint weights[16] = {0,4,9,13,17,21,26,30,34,38,43,47,51,55,60,64};
uint blockOutputIndex(uint2 gid, constant Params &p) {
#if TILE_MAJOR_ENCODER
    uint tileY=gid.y/32, tileX=gid.x/32;
    uint tileHeight=min(128u,p.height-tileY*128u);
    return tileY*(p.width*8u)+tileX*(tileHeight*8u)+(gid.y%32u)*32u+gid.x%32u;
#else
    return gid.y*(p.width/4)+gid.x;
#endif
}
// Independent 4x4 blocks. Mode 6 is universally decodable by a BC7-capable GPU.
kernel void encodeBC7(texture2d<float, access::read> src [[texture(0)]],
    device uint4 *output [[buffer(0)]], device const uint4 *previous [[buffer(1)]],
    device atomic_uint *dirty [[buffer(2)]], constant Params &p [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= p.width/4 || gid.y >= p.height/4) return;
    float3 colors[16]; float3 mean=0;
    for (uint i=0;i<16;i++) { colors[i]=round(clamp(src.read(gid*4+uint2(i%4,i/4)).rgb,0.0f,1.0f)*255.0f); mean+=colors[i]; }
    mean/=16.0f;
    float3 lo=colors[0],hi=colors[0];
    for(uint i=1;i<16;i++) {lo=min(lo,colors[i]);hi=max(hi,colors[i]);}
#if !BASELINE_ENCODER
    // A flat desktop block needs no PCA or 16-way palette search. Select the
    // same shared parity and endpoints as the general encoder, bit for bit.
    if(all(lo==hi)) {
        float best=1e20f; uint3 q=0; uint parity=0;
        for(uint b=0;b<2;b++) {
            uint3 t=uint3(clamp(round((lo-float(b))/2.0f),0.0f,127.0f));
            float3 d=float3(t*2+b)-lo; float err=dot(d,d);
            if(err<best){best=err;q=t;parity=b;}
        }
        uint4 bits=0; uint pos=0; putbits(bits,pos,64,7);
        for(uint c=0;c<3;c++){putbits(bits,pos,q[c],7);putbits(bits,pos,q[c],7);}
        putbits(bits,pos,127,7);putbits(bits,pos,127,7);putbits(bits,pos,parity,1);putbits(bits,pos,parity,1);
        // Remaining palette indices are all zero.
        uint index=blockOutputIndex(gid,p);output[index]=bits;
        if(p.force || any(bits!=previous[index])) atomic_fetch_or_explicit(&dirty[(gid.y/32)*p.columns+(gid.x/32)],1,memory_order_relaxed);
        return;
    }
#endif
    float3 axis=hi-lo;
    for(uint n=0;n<3;n++) { float3 next=0; for(uint i=0;i<16;i++){float3 d=colors[i]-mean;next+=d*dot(d,axis);} if(dot(next,next)>0.001f) axis=normalize(next); }
    float minP=1e20f,maxP=-1e20f;
    if(dot(axis,axis)<0.001f) axis=float3(1,0,0);
    for(uint i=0;i<16;i++){float v=dot(colors[i]-mean,axis);minP=min(minP,v);maxP=max(maxP,v);}
    float3 endpoints[2]={clamp(mean+axis*minP,0.0f,255.0f),clamp(mean+axis*maxP,0.0f,255.0f)};
    uint3 q[2]; uint parity[2]; uint3 actual[2];
    for(uint e=0;e<2;e++) {
        float best=1e20f;
        for(uint b=0;b<2;b++) {
            uint3 t=uint3(clamp(round((endpoints[e]-float(b))/2.0f),0.0f,127.0f));
            float3 d=float3(t*2+b)-endpoints[e]; float err=dot(d,d);
            if(err<best){best=err;q[e]=t;parity[e]=b;actual[e]=t*2+b;}
        }
    }
    uint indices[16];
    for(uint i=0;i<16;i++) {
        float best=1e20f; uint chosen=0;
        for(uint j=0;j<16;j++) {
            uint3 rgb=((64-weights[j])*actual[0]+weights[j]*actual[1]+32)/64;
            float3 d=float3(rgb)-colors[i];float err=dot(d,d);
            if(err<best){best=err;chosen=j;}
        }
        indices[i]=chosen;
    }
    if(indices[0]>=8){uint3 temp=q[0];q[0]=q[1];q[1]=temp;uint b=parity[0];parity[0]=parity[1];parity[1]=b;for(uint i=0;i<16;i++)indices[i]=15-indices[i];}
    uint4 bits=0;uint pos=0;putbits(bits,pos,64,7);
    for(uint c=0;c<3;c++){putbits(bits,pos,q[0][c],7);putbits(bits,pos,q[1][c],7);}
    putbits(bits,pos,127,7);putbits(bits,pos,127,7);putbits(bits,pos,parity[0],1);putbits(bits,pos,parity[1],1);
    for(uint i=0;i<16;i++)putbits(bits,pos,indices[i],i==0?3:4);
    uint index=blockOutputIndex(gid,p);output[index]=bits;
    if(p.force || any(bits!=previous[index])) atomic_fetch_or_explicit(&dirty[(gid.y/32)*p.columns+(gid.x/32)],1,memory_order_relaxed);
}
struct Vertex { float4 position [[position]]; float2 uv; };
vertex Vertex screenVertex(uint id [[vertex_id]]) {
    float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};
    Vertex v;v.position=float4(p[id],0,1);v.uv=float2((p[id].x+1)/2,(1-p[id].y)/2);return v;
}
fragment float4 screenFragment(Vertex in [[stage_in]],texture2d<float> image [[texture(0)]]) {
    constexpr sampler s(filter::nearest,address::clamp_to_edge);
    return float4(image.sample(s,in.uv).rgb,1);
}
