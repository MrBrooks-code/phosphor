#include <metal_stdlib>
using namespace metal;
// Keep this layout in step with GPUUniforms in Renderer.swift.
struct Uniforms {
    float2 resolution; float time; float dt;
    float bass; float mid; float high; float transient;
    float rms; float intensity; float persistence; float phase;
    uint scene; uint palette; float travel; float reactivity;
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
// Small analytic fields bound the work per pixel. Motion uses seconds, not frame counts.
float response(float value, float reactivity) { return min(1.5,max(0.,value)*clamp(reactivity,0.,2.)); }
float hash21(float2 p) { return fract(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
float2 turn(float2 p, float a) { return float2(cos(a)*p.x-sin(a)*p.y,sin(a)*p.x+cos(a)*p.y); }
float edgeLight(float d, float width) { return exp(-abs(d)/max(width,.0001)); }
float mountain(float x, float seed) {
    float cell=floor(x), f=fract(x);
    return mix(hash21(float2(cell,seed)),hash21(float2(cell+1,seed)),f);
}
// A fixed horizon separates the skyline and mountain silhouettes from the advancing floor.
float3 outrunScene(float2 p, thread const Uniforms &u, device const float *spectrum) {
    float horizon=.18, y=p.y-horizon, px=2/u.resolution.y;
    float3 base=ink(0,u.palette), bright=ink(1,u.palette);
    float3 c=base*(.018+.055*exp(-abs(y)*3));
    float2 sun=p-float2(.34,-.34);
    float r=length(sun), radius=.34;
    c+=base*exp(-r*r*5)*.18;
    float stripe=smoothstep(.18,.23,fract((sun.y+.4)*19));
    float disc=1-smoothstep(radius-px,radius+px,r);
    c+=mix(bright,base,clamp(sun.y*1.6+.45,0.,1.))*disc*stripe*.85;
    float2 cell=floor((p+4)*55), local=fract((p+4)*55)-.5;
    float star=edgeLight(length(local),.045)*step(.975,hash21(cell));
    c+=bright*star*(.2+u.high*.9)*step(p.y,-.14)*( .7+.3*sin(u.time*.8+hash21(cell)*50));
    for(int layer=0;layer<3;layer++) {
        float ridge=horizon-.025-float(layer)*.018-mountain(p.x*(5+layer*2)+u.phase*.15,12+layer)*(.24-float(layer)*.045);
        float mask=smoothstep(ridge-px,ridge+px,p.y);
        c=mix(c,base*(.013+float(layer)*.012),mask);
        c+=base*edgeLight(p.y-ridge,.003)*.12;
    }
    float column=floor((p.x+3)*19), band=response(spectrum[min(uint(fract(column*.037)*64),63u)],u.reactivity);
    float height=.018+hash21(float2(column,4))*.07+band*.17+u.bass*.055;
    float building=step(.15,fract((p.x+3)*19))*step(horizon-height,p.y)*step(p.y,horizon);
    c=mix(c,base*.015,building);
    c+=bright*building*step(.8,fract(p.y*210))*step(.65,fract(p.x*180))*(.18+u.transient*.8);
    if(y>0) {
        float terrain=.25+u.bass*.045;
        float z=terrain/max(y,.002), x=p.x*z;
        float dx=abs(fract(x+.5)-.5)/z;
        float dz=abs(fract(z-u.travel*4+.5)-.5)*y*y/terrain;
        float fade=smoothstep(.025,.18,y);
        float grid=(edgeLight(dx,px*.75)+edgeLight(dz,px*.75))*fade;
        c=base*.012+mix(base,bright,.3)*grid*(.48+.65*u.bass+u.transient*.7);
        float pulse=edgeLight(y-(.32+u.bass*.32),.012)*u.transient;
        c+=bright*pulse*.24;
        c+=base*exp(-y*25)*.12;
    }
    return c*u.intensity;
}
// Three counter-rotating diamond crowns keep separate bass, mid, and air structures.
float3 crystalScene(float2 p, thread const Uniforms &u, device const float *spectrum) {
    float r=length(p), a=atan2(p.y,p.x), px=2/u.resolution.y;
    float3 c=ink(0,u.palette)*exp(-r*r*4)*.025;
    for(int layer=0;layer<3;layer++) {
        float n=12+layer*4, spin=u.time*(layer==1 ? -.035:.025)+u.phase*.15;
        float sector=(a+spin)*n/6.283185;
        float f=fract(sector+.5)-.5;
        uint band=uint(layer*20)+min(uint(abs(f)*38),19u);
        float energy=response(spectrum[min(band,63u)],u.reactivity);
        float response=layer==0 ? u.high : (layer==1 ? u.mid:u.bass);
        float center=(.25+float(layer)*.235)*(1+response*.11+u.transient*.035);
        float halfLength=.105+response*.065+energy*.055;
        float width=.27+float(layer)*.025;
        float diamond=abs(r-center)/halfLength+abs(f)/width;
        float face=1-smoothstep(1.,1.+px*10,diamond);
        float seam=edgeLight(diamond-1,px*7);
        float spine=edgeLight(f,px*1.2)*face;
        float facet=(f>0 ? .12:.3)+(r>center ? .0:.14);
        float3 tint=ink(clamp(float(layer)*.25+f+.35,0.,1.),u.palette);
        c+=tint*(face*facet*(1.6+response*.4)+seam*(.55+u.transient*.6)+spine*.35);
        c+=ink(1,u.palette)*face*u.transient*pow(max(0.,cos(a*3+u.time*.6+layer)),16)*.65;
        float polygon=r*cos(f*6.283185/n);
        c+=tint*edgeLight(r-(center+.025*cos((a+spin)*n*2)),px)*.07;
        c+=tint*edgeLight(polygon-(center-halfLength-.025),px)*.16;
    }
    float hex=length(p)*cos(fmod(a+9.424778,1.047198)-.523599);
    c+=ink(1,u.palette)*(edgeLight(hex-.103,px)*.6+exp(-r*25)*(.15+.25*u.bass));
    return c*u.intensity;
}
// Sample nearby polar cells instead of testing a global particle list at every pixel.
float3 galaxyScene(float2 p, thread const Uniforms &u) {
    float2 q=turn(p,-.28); q.y/=.69;
    q/=1+u.bass*.085;
    float r=length(q), a=atan2(q.y,q.x), px=2/u.resolution.y;
    float theta=(a-3.2*log(r+.14)-u.time*.022-u.phase*.1-u.mid*.08)/6.283185;
    float arm=.5+.5*cos(theta*25.132741);
    float disc=exp(-r*2.6)*smoothstep(.035,.2,r)*(1-smoothstep(1.,1.45,r));
    float3 c=ink(.15,u.palette)*pow(arm,8)*disc*(.36+u.mid*.32);
    for(int layer=0;layer<2;layer++) {
        float radial=48+layer*19, angular=96;
        float2 grid=float2(r*radial,fract(theta)*angular);
        float2 origin=floor(grid);
        for(int x=-1;x<=1;x++) for(int y=-1;y<=1;y++) {
            float2 id=origin+float2(x,y);
            float2 wrapped=float2(id.x,fmod(id.y+angular,angular));
            float h=hash21(wrapped+float(layer)*73);
            float2 offset=float2(hash21(wrapped+13),hash21(wrapped+31));
            float2 delta=id+offset-grid;
            float rr=max((id.x+offset.x)/radial,.015);
            float da=delta.y/angular*6.283185;
            // Account for the spiral shear in the local radial direction.
            float2 distance=float2(delta.x/radial,(da+3.2/(rr+.14)*delta.x/radial)*rr);
            float shape=exp(-dot(distance,distance)/(max(px,.0015)*max(px,.0015)*(.4+h)*1.6));
            float trail=exp(-abs(distance.x)*450-abs(distance.y)*110)*.12*u.persistence;
            float armPhase=(id.y+offset.y)/angular*25.132741;
            float density=pow(.5+.5*cos(armPhase),9);
            uint armID=uint(floor(fract((id.y+offset.y)/angular)*4));
            float band=armID==0 ? u.bass : (armID==1 ? u.mid : (armID==2 ? u.high:(u.mid+u.high)*.5));
            float sparkle=step(.6,h)*u.transient;
            c+=ink(h,u.palette)*(shape+trail)*density*disc*(.9+band*2.2+sparkle)*(.5+float(layer)*.4);
        }
    }
    c+=ink(1,u.palette)*exp(-r*r/(.004+u.bass*.009))*(1.2+u.bass*.3);
    c+=ink(.6,u.palette)*exp(-r*8)*.15;
    c+=ink(.8,u.palette)*edgeLight(r-(.24+u.bass*.22),px*2)*u.transient*.55;
    return c*u.intensity;
}
// Seeded 5 by 7 numerals and runes retain clear stems, counters, and crossbars.
float glyph(float2 cell, float seed) {
    int x=int(floor(cell.x*7))-1, y=int(floor(cell.y*9))-1;
    if(x<0 || x>4 || y<0 || y>6) return 0;
    const uint2 symbols[16]={uint2(0xace2e,0x3a39),uint2(0x21184,0x3884),uint2(0x3062e,0x7e08),uint2(0x2083f,0x2108),uint2(0xfc62e,0x4631),uint2(0xf421f,0x7e10),uint2(0xfc631,0x4631),uint2(0xc5251,0x4654),uint2(0x9d731,0x4631),uint2(0x22a31,0x1084),uint2(0x713e4,0x1095),uint2(0xf905f,0x4104),uint2(0x97e52,0x2082),uint2(0x27c8e,0x12b5),uint2(0x7085e,0x3a52),uint2(0x27dd5,0x455f)};
    uint2 bits=symbols[min(uint(seed*16),15u)];
    uint row=y<4 ? bits.x>>uint(y*5) : bits.y>>uint((y-4)*5);
    return float((row>>uint(4-x))&1u);
}
// Two spaced depth layers have stable stream speeds and bright moving heads.
float3 rainScene(float2 p, thread const Uniforms &u, device const float *spectrum) {
    float3 c=0;
    for(int layer=0;layer<2;layer++) {
        float size=layer==0 ? .044:.069;
        float2 g=(p+float2(7,3))/float2(size,size*1.65);
        float col=floor(g.x), row=floor(g.y);
        float seed=hash21(float2(col,layer+17));
        float speed=2.5+seed*5, period=45+seed*30;
        float head=u.time*speed+u.bass*2.4+seed*period+u.phase*3;
        float age=fmod(head-row+period*100,period);
        float length=9+seed*18+u.bass*5;
        float band=response(spectrum[min(uint(fract(col*.023+float(layer)*.2)*64),63u)],u.reactivity);
        float cluster=step(.48,hash21(float2(floor(col/4),layer+5)));
        float active=step(seed, .58+band*.2)+cluster*u.transient*.65;
        float fade=pow(max(0.,1-age/length),1.7)*active;
        float tick=floor(u.time*2+seed*13);
        float symbol=hash21(float2(col*7+row,tick));
        float mask=glyph(fract(g),symbol);
        float headLight=1-smoothstep(.0,1.5,age);
        float sparkle=step(.985,hash21(float2(row+tick,col)))*u.high;
        float3 tint=mix(ink(.1,u.palette),ink(1,u.palette),headLight);
        c+=tint*mask*fade*(.48+band*.8+headLight*(1.3+cluster*u.transient*1.4)+sparkle)*(layer==0 ? .45:1.);
    }
    return c*u.intensity;
}
// Five soft sources make a continuous field. Contours show flow without feedback recursion.
float3 plasmaScene(float2 p, thread const Uniforms &u) {
    float t=u.time*.075+u.phase, field=0;
    float2 warp=p+.065*float2(sin(p.y*3+t),cos(p.x*2-t*.7))*(.5+u.mid*1.4);
    for(int i=0;i<5;i++) {
        float k=float(i), phase=k*1.256637;
        float2 center=float2(sin(t*(.42+k*.07)+phase)*1.05,cos(t*(.51+k*.04)+phase)*.68);
        center*=1+u.bass*.16;
        float2 d=warp-center;
        float radius=.38+k*.055+u.bass*.09;
        field+=exp(-dot(d,d)/radius)*(.62+k*.045);
    }
    float contours=field*7+u.mid*.4+.18*sin(p.x*3+p.y*2+t);
    float ridge=pow(.5+.5*cos(contours*6.283185),18);
    float fill=smoothstep(.2,1.4,field);
    float colorPosition=.5+.5*sin(field*3.8-t*.2);
    float3 deep=ink(0,u.palette)*float3(.15,.12,.2);
    float3 c=mix(deep,ink(colorPosition,u.palette)*.72,fill);
    c+=ink(1-colorPosition,u.palette)*ridge*fill*(.3+u.high*.2);
    float accent=exp(-pow(field-1.05,2)*90)*u.transient*.5;
    c+=ink(1,u.palette)*accent;
    return c*u.intensity;
}

fragment float4 sceneFragment(VertexOut in [[stage_in]], constant Uniforms &input [[buffer(0)]],
    device const float2 *wave [[buffer(1)]], device const float *spectrum [[buffer(2)]],
    texture2d<float> previous [[texture(0)]]) {
    Uniforms u=input;
    u.bass=response(u.bass,u.reactivity); u.mid=response(u.mid,u.reactivity);
    u.high=response(u.high,u.reactivity); u.transient=response(u.transient,u.reactivity);
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv=in.uv, p=(uv-.5)*2; p.x*=u.resolution.x/u.resolution.y;
    float px=2/u.resolution.y; float3 color=0;
    float t=u.time, phase=u.phase;
    if(u.scene==0) {
        float grid=(exp(-abs(p.x)*500)+exp(-abs(p.y)*500))*.025;
        float rings=exp(-abs(length(p)-.78)*400)*.018;
        color=ink(0,u.palette)*(grid+rings)*u.intensity;
        float decay=exp(-u.dt/(.04+u.persistence*.7));
        color=max(color, previous.sample(s,uv).rgb*decay);
        // The lower spectrum keeps upper-frequency detail separate from the X/Y trace.
        if(uv.y>.89 && uv.y<.97 && fract(uv.x*64)>.13) {
            uint band=min(uint(uv.x*64),63u);
            float h=response(spectrum[band],u.reactivity)*.075;
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
    } else if(u.scene==2) {
        float2 center=float2(sin(t*.19+phase)*.16,cos(t*.13+phase)*.12);
        float2 q=p-center; float r=length(q), a=atan2(q.y,q.x)+.10*sin(t*.17)+u.mid*.08;
        float light=0;
        for(int i=0;i<22;i++) {
            float z=fract(float(i)/22+u.travel);
            float depth=(.055+z*z*2.5)*(1+u.bass*.07);
            float polygon=cos(3.14159265/6)/cos(fmod(a+6.283185,6.283185/6)-3.14159265/6);
            float d=abs(r-depth*polygon);
            light+=exp(-d/max(px,px*depth))*(.12+z*.55)*(1+u.transient*.9);
        }
        float spokes=exp(-abs(sin(a*6))*r*220)*smoothstep(.1,.8,r)*(.08+u.high*.55);
        color=ink(clamp(r*.55,0.,1.),u.palette)*(light+spokes)*u.intensity;
        color+=ink(1,u.palette)*exp(-r*30)*(.3+u.bass)*u.intensity;
    }
    else if(u.scene==3) color=outrunScene(p,u,spectrum);
    else if(u.scene==4) color=crystalScene(p/min(1.,u.resolution.x/u.resolution.y),u,spectrum);
    else if(u.scene==5) {
        color=galaxyScene(p/min(1.,u.resolution.x/u.resolution.y),u);
        float decay=exp(-u.dt/(.025+u.persistence*.13));
        color=max(color,previous.sample(s,uv).rgb*decay);
    }
    else if(u.scene==6) color=rainScene(p,u,spectrum);
    else if(u.scene==7) color=plasmaScene(p,u);
    if(u.intensity<=0) color=0;
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
    float scale=1.7*(.35+.65*clamp(u.reactivity,0.,2.));
    float2 a=wave[segment]*scale, b=wave[segment+1]*scale;
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
