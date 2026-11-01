#include <metal_stdlib>
using namespace metal;
// Keep this layout in step with GPUUniforms in Renderer.swift.
struct Uniforms {
    float2 resolution; float time; float dt;
    float bass; float mid; float high; float transient;
    float rms; float intensity; float persistence; float phase;
    uint scene; uint palette; float2 padding;
};
struct VertexOut { float4 position [[position]]; float2 uv; };
vertex VertexOut fullscreen(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p*2-1,0,1), float2(p.x,1-p.y)};
}
float3 ink(float t, uint palette) {
    if (palette == 0) return mix(float3(0.08,0.85,0.56),float3(0.65,1,0.83),t);
    if (palette == 1) return mix(float3(1,0.16,0.035),float3(1,0.77,0.25),t);
    if (palette == 2) return mix(float3(0.49,0.12,1),float3(1,0.32,0.68),t);
    return mix(float3(0.08,0.38,1),float3(0.5,0.94,1),t);
}
float line(float2 p, float2 a, float2 b) {
    float2 d=b-a; float h=clamp(dot(p-a,d)/max(dot(d,d),1e-8),0.,1.);
    return length(p-a-d*h);
}
fragment float4 sceneFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]],
    device const float2 *wave [[buffer(1)]], device const float *spectrum [[buffer(2)]],
    texture2d<float> previous [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv=in.uv, p=(uv-.5)*2; p.x*=u.resolution.x/u.resolution.y;
    float px=2/u.resolution.y; float3 color=0;
    float t=u.time, phase=u.phase;
    if(u.scene==0) {
        float grid=(exp(-abs(p.x)*500)+exp(-abs(p.y)*500))*.025;
        float rings=exp(-abs(length(p)-.78)*400)*.018;
        color=ink(0,u.palette)*(grid+rings);
        float decay=exp(-u.dt/(.04+u.persistence*.7));
        color=max(color, previous.sample(s,uv).rgb*decay);
        // The lower spectrum keeps upper-frequency detail separate from the X/Y trace.
        if(uv.y>.89 && uv.y<.97 && fract(uv.x*64)>.13) {
            uint band=min(uint(uv.x*64),63u);
            float h=spectrum[band]*.075;
            if(h>.0001) color+=ink(float(band)/64,u.palette)*(1-smoothstep(0.,px,abs(uv.y-.96+h*.5)-h*.5))*.5*u.intensity;
        }
    } else if(u.scene==1) {
        float r=length(p), angle=atan2(p.y,p.x);
        float rotation=u.dt*(.10+u.mid*.35);
        float2 q=p*(1-u.dt*(.035+u.bass*.12));
        q=float2(cos(rotation)*q.x-sin(rotation)*q.y,sin(rotation)*q.x+cos(rotation)*q.y);
        q+=u.dt*.022*float2(sin(p.y*5+t*.4),cos(p.x*5-t*.3));
        float2 sampleUV=q/float2(u.resolution.x/u.resolution.y,1)*.5+.5;
        float3 trail=previous.sample(s,sampleUV).rgb*exp(-u.dt*(.65+(1-u.persistence)*2));
        float petals=.47+.13*sin(angle*5+t*.22+phase)+.06*sin(angle*9-t*.32);
        float edge=abs(r-petals-u.bass*.17);
        float ribbon=exp(-edge*(70-35*u.high))*(.09+u.mid*.65);
        float filaments=pow(.5+.5*sin(angle*23+r*21-t),16)*exp(-abs(r-.9)*10)*u.high;
        float flare=exp(-r*r*9)*u.transient;
        color=trail+ink(.5+.5*sin(angle+t*.15),u.palette)*(ribbon+filaments*.7+flare*.4)*u.intensity*min(u.dt*60,2.);
    } else {
        float2 center=float2(sin(t*.19+phase)*.16,cos(t*.13+phase)*.12);
        float2 q=p-center; float r=length(q), a=atan2(q.y,q.x)+.10*sin(t*.17);
        float light=0;
        for(int i=0;i<22;i++) {
            float z=fract(float(i)/22+u.padding.x);
            float depth=.055+z*z*2.5;
            float polygon=cos(3.14159265/6)/cos(fmod(a+6.283185,6.283185/6)-3.14159265/6);
            float d=abs(r-depth*polygon);
            light+=exp(-d/max(px,px*depth))*(.12+z*.55)*(1+u.transient*.9);
        }
        float spokes=exp(-abs(sin(a*6))*r*220)*smoothstep(.1,.8,r)*(.08+u.high*.55);
        color=ink(clamp(r*.55,0.,1.),u.palette)*(light+spokes)*u.intensity;
        color+=ink(1,u.palette)*exp(-r*30)*(.3+u.bass);
    }
    color*=(1-smoothstep(.3,1.8,length((uv-.5)*1.3)));
    return float4(min(color,float3(8)),1);
}
fragment float4 presentFragment(VertexOut in [[stage_in]], texture2d<float> image [[texture(0)]]) {
    constexpr sampler s(filter::linear); float3 c=image.sample(s,in.uv).rgb;
    return float4(1-exp(-c*1.25),1);
}

struct TraceOut { float4 position [[position]]; float2 local; float length; float age; };
// Expand each stereo segment to a small quad. This bounds trace work to its visible area.
vertex TraceOut scopeVertex(uint vertexID [[vertex_id]], uint segment [[instance_id]],
    constant Uniforms &u [[buffer(0)]], device const float2 *wave [[buffer(1)]]) {
    float2 a=wave[segment]*1.7, b=wave[segment+1]*1.7;
    float2 delta=b-a; float len=max(length(delta),.00001);
    float2 direction=delta/len, normal=float2(-direction.y,direction.x);
    float radius=18/u.resolution.y;
    const float2 corners[6]={float2(0,-1),float2(1,-1),float2(0,1),float2(0,1),float2(1,-1),float2(1,1)};
    float2 c=corners[vertexID]; float x=mix(-radius,len+radius,c.x);
    float2 p=a+direction*x+normal*c.y*radius;
    p.x/=u.resolution.x/u.resolution.y; p.y=-p.y;
    return {float4(p,0,1),float2(x,c.y*radius),len,float(segment)/511};
}
fragment float4 scopeFragment(TraceOut in [[stage_in]],constant Uniforms &u [[buffer(0)]]) {
    float d=length(float2(in.local.x-clamp(in.local.x,0.,in.length),in.local.y));
    float px=2/u.resolution.y;
    float brightness=(exp(-d*d/(px*px*1.6))*.10+exp(-d*100)*.009)*(.15+.85*in.age)*u.intensity;
    return float4(ink(.6,u.palette)*brightness,0);
}
