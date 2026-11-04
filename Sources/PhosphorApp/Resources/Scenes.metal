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

#if PHOSPHOR_V2
// The route bends through dark terrain. Only road markers use integrated travel.
float3 outrunV2(float2 p, thread const Uniforms &u, device const float *spectrum) {
    float px=2/u.resolution.y, horizon=.045+.009*sin(u.time*.045+u.phase);
    float y=p.y-horizon, camera=.045*sin(u.time*.035+u.phase);
    float3 dark=ink(0,u.palette), light=ink(1,u.palette);
    float3 c=dark*(.008+.07*exp(-abs(y)*5));
    float2 sun=p-float2(-.52-camera,-.34);
    float r=length(sun), disc=1-smoothstep(.245-px,.245+px,r);
    float eclipse=smoothstep(.226-px,.226+px,length(sun-float2(.043,-.025)));
    c+=mix(dark,light,.65)*disc*(.10+.52*eclipse);
    c+=light*edgeLight(r-.245,px*1.3)*.22;
    c+=dark*exp(-r*r*9)*.07;
    // Far ridges move less than the near silhouettes.
    for(int layer=0;layer<3;layer++) {
        float k=float(layer), x=p.x*(3+k*1.7)+camera*(.3+k*.5);
        float ridge=horizon-.035-(.09+k*.033)*mountain(x,34+k)-.035*sin(x*.8+k);
        float mask=smoothstep(ridge-px,ridge+px,p.y);
        c=mix(c,dark*(.048-k*.011),mask);
        c+=dark*edgeLight(p.y-ridge,px*1.2)*(.10-k*.022);
    }
    float cityX=p.x+.1+camera*.25, col=floor(cityX*37);
    float band=response(spectrum[min(uint(fract(col*.071+2)*64),63u)],u.reactivity);
    float cluster=exp(-cityX*cityX*4);
    float height=(.025+.12*pow(hash21(float2(col,6)),3)+band*.055)*cluster;
    float tower=step(.23,fract(cityX*37))*step(horizon-height,p.y)*step(p.y,horizon);
    c=mix(c,dark*.012,tower);
    c+=light*tower*step(.88,fract(p.y*310))*step(.67,fract(cityX*170))*(.14+u.mid*.16);
    c+=light*edgeLight(p.y-horizon+height,px)*tower*(.10+u.high*.2);
    if(y>0) {
        float z=.55/max(y,.002), worldX=p.x*z+camera;
        float bend=.78*sin(z*.22)+.22*sin(z*.51);
        float road=worldX-bend, halfWidth=.66;
        float distanceToRoad=abs(road)-halfWidth;
        float fog=1-exp(-y*7), roadMask=1-smoothstep(-px*z,px*z,distanceToRoad);
        float strata=sin(worldX*2.5+z*.55)+.35*sin(worldX*6-z*.31);
        float slope=cos(worldX*2.5+z*.55)*.6+.3*cos(worldX*6-z*.31);
        float terraces=abs(fract(strata*2.2)-.5);
        float contour=1-smoothstep(.015,.015+max(fwidth(strata)*2.2,.002),terraces);
        float terrainLight=.028+.065*max(0.,slope)+contour*.025;
        c=dark*terrainLight*fog;
        c=mix(c,dark*(.018+.036*exp(-road*road*4)),roadMask);
        float rails=edgeLight(distanceToRoad/z,px*.85)*fog;
        float markers=pow(.5+.5*cos((z-u.travel*40)*6.283185/2),24);
        c+=mix(dark,light,.62)*rails*(.32+.23*markers+u.transient*markers*.9);
        float centerLine=edgeLight(road/z,px*.7)*step(.54,fract((z-u.travel*40)*.5));
        c+=light*centerLine*fog*.13;
        float shoulder=edgeLight((abs(road)-.84)/z,px)*markers*fog;
        c+=dark*shoulder*(.12+u.bass*.3);
        float reflection=exp(-pow((road+.28)/.21,2))*exp(-y*7)*roadMask;
        c+=light*reflection*(.11+u.bass*.07);
        // Low cliffs frame the route without adding objects to its silhouette.
        float cliff=horizon+.15+.10*sin(p.x*2.6+camera)-.23*pow(abs(p.x),1.3);
        float cliffMask=smoothstep(cliff-px,cliff+px,p.y)*smoothstep(.9,1.7,abs(p.x));
        c=mix(c,dark*.009,cliffMask);
        c+=dark*edgeLight(p.y-cliff,px*1.2)*smoothstep(.9,1.7,abs(p.x))*.12;
        c+=dark*exp(-y*35)*.09;
    }
    return c*u.intensity;
}
float3 rotateX(float3 p,float a) { p.yz=turn(p.yz,a); return p; }
float3 rotateY(float3 p,float a) { p.xz=turn(p.xz,a); return p; }
float3 rotateZ(float3 p,float a) { p.xy=turn(p.xy,a); return p; }
// Clip a ray against eight planes. The nearest visible face owns each pixel.
float octahedron(float3 ro,float3 rd,thread float3 &normal) {
    float nearT=0, farT=100;
    for(int face=0;face<8;face++) {
        float3 n=float3((face&1) ? 1.:-1.,(face&2) ? 1.:-1.,(face&4) ? 1.:-1.);
        float denom=dot(n,rd), room=1-dot(n,ro);
        if(abs(denom)<.000001) { if(room<0) return -1; }
        else {
            float t=room/denom;
            if(denom<0 && t>nearT) { nearT=t; normal=n; }
            if(denom>0) farT=min(farT,t);
        }
    }
    return nearT<farT && farT>0 ? nearT:-1;
}
// Eight solid prisms form a mechanical iris with a clear central opening.
float3 crystalV2(float2 p, thread const Uniforms &u, device const float *spectrum) {
    float3 c=ink(0,u.palette)*.006;
    float tilt=.32+.12*sin(u.time*.07+u.phase), spin=u.time*.035+u.phase*.12;
    float3 ro=rotateY(float3(0,0,3.4),tilt);
    float3 rd=rotateY(normalize(float3(p.x,-p.y,-3)),tilt);
    float nearest=100;
    for(int i=0;i<8;i++) {
        float a=float(i)*.785398+spin;
        float energy=response(spectrum[i*7],u.reactivity);
        float radius=.53+u.bass*.035;
        float3 center=float3(cos(a)*radius,sin(a)*radius,.08*sin(a*2));
        float fold=.3+.14*sin(u.time*.11+float(i)*.4)+u.mid*.16;
        float3 scale=float3(.255,.48+energy*.035,.22);
        float3 localRO=rotateX(rotateZ(ro-center,-a+1.570796),fold)/scale;
        float3 localRD=rotateX(rotateZ(rd,-a+1.570796),fold)/scale;
        float3 normal=0; float hit=octahedron(localRO,localRD,normal);
        if(hit>0 && hit<nearest) {
            nearest=hit;
            float3 point=localRO+localRD*hit;
            float3 n=normalize(rotateZ(rotateX(normal/scale,-fold),a-1.570796));
            float diffuse=max(0.,dot(n,normalize(float3(-.6,.8,1.2))));
            float spec=pow(max(0.,dot(reflect(-normalize(float3(-.6,.8,1.2)),n),-rd)),32);
            float bevel=exp(-min(abs(point.x),min(abs(point.y),abs(point.z)))*170);
            float facet=.045+diffuse*.42;
            float engraving=pow(.5+.5*cos((point.y+point.z*.3)*95),36)*.015;
            float3 tint=ink(clamp(.35+n.y*.4,0.,1.),u.palette);
            float select=.5+.5*sin(float(i)*2.4+u.time*.23);
            c=tint*(facet+engraving)+mix(tint,float3(1),.55)*(spec*.48+bevel*(.12+u.high*.14));
            c+=ink(1,u.palette)*bevel*pow(select,8)*u.transient*.75;
        }
    }
    float r=length(p);
    if(nearest==100) c+=ink(.6,u.palette)*exp(-r*14)*(.035+u.bass*.025);
    return c*u.intensity;
}
float spiralArm(float2 q,float clock) {
    float r=length(q), a=atan2(q.y,q.x);
    float phase=a-2.65*log(r+.13)-clock;
    float primary=pow(.5+.5*cos(phase*3),12);
    float branch=pow(.5+.5*cos(phase*3+1.1+sin(r*8)*.5),22)*.32;
    return (primary+branch)*(1-smoothstep(.9,1.65,r))*smoothstep(.08,.21,r);
}
// Three star sheets and dark dust lanes make an inclined, asymmetric volume.
float3 galaxyV2(float2 p, thread const Uniforms &u) {
    float3 c=0; float px=2/u.resolution.y;
    float clock=u.time*.018+u.phase*.13;
    float2 parallax=float2(sin(u.time*.045+u.phase),cos(u.time*.037))*.018;
    for(int layer=0;layer<3;layer++) {
        float k=float(layer);
        float2 q=turn(p+parallax*(k-1),-.35); q.y/=.58+k*.055;
        q/=(.90+k*.12)*(1+u.bass*.018);
        q=turn(q,-clock*.3/(.5+length(q)));
        float r=length(q), arm=spiralArm(q,clock+u.mid*.025);
        float dust=.5+.5*sin(q.x*26+sin(q.y*17)*1.6+clock);
        float opacity=mix(.22,1.,smoothstep(.3,.72,dust));
        c+=ink(.18+k*.12,u.palette)*arm*exp(-r*1.4)*opacity*.07;
        float cells=37+k*17;
        float2 grid=q*cells, origin=floor(grid);
        for(int x=-1;x<=1;x++) for(int y=-1;y<=1;y++) {
            float2 id=origin+float2(x,y), h=float2(hash21(id+k*31),hash21(id+17+k*37));
            float2 point=(id+h)/cells;
            float density=spiralArm(point,clock+u.mid*.025);
            float2 d=(id+h-grid)/cells;
            float size=max(px*.65,.0013)*(.45+h.x*1.3);
            float star=exp(-dot(d,d)/(size*size));
            float cluster=.5+.5*sin(point.x*11+point.y*7);
            float event=u.transient*pow(cluster,12)*step(.7,h.x);
            float band=layer==0 ? u.bass:(layer==1 ? u.mid:u.high);
            c+=mix(ink(h.x,u.palette),float3(.9,.91,.86),h.x*.35)*star*density*opacity*(.30+band*.7+event)*exp(-length(point)*.9);
        }
    }
    float2 core=turn(p,-.35); core.y/=.65;
    float r=length(core);
    float bulge=exp(-r*r*53)*(.34+u.bass*.12);
    float dustLane=smoothstep(.012,.06,abs(core.y+.025*sin(core.x*18)));
    c+=mix(ink(1,u.palette),float3(1,.87,.69),.38)*bulge*(.26+.74*dustLane);
    c+=ink(.9,u.palette)*exp(-r*r*800)*.33;
    return c*u.intensity;
}
// Shared wave fronts group the streams. Empty lanes remain part of the composition.
float3 rainV2(float2 p, thread const Uniforms &u, device const float *spectrum) {
    float3 c=0;
    for(int layer=0;layer<3;layer++) {
        float k=float(layer), size=.026+k*.022;
        float wave=sin(p.x*2.2-u.time*.16+u.phase);
        float2 q=p+float2(sin(p.y*1.2+u.time*.1)*u.bass*.012*(k+1),0);
        float2 g=(q+float2(7,3))/float2(size,size*1.65);
        float col=floor(g.x), row=floor(g.y), group=floor(col/5);
        float seed=hash21(float2(col,21+layer)), groupSeed=hash21(float2(group,3+layer));
        float band=response(spectrum[min(uint(fract(group*.117+1)*64),63u)],u.reactivity);
        float period=60, speed=2.3+k*.8;
        float head=u.time*speed+groupSeed*period+wave*3+seed*3+u.phase*4;
        float age=fract((head-row)/period)*period;
        float tail=7+seed*9+band*7;
        float lane=step(.18,seed)*step(groupSeed,.32+band*.30);
        float crest=exp(-pow(p.y-wave*.38,2)*18);
        float event=crest*u.transient*step(.35,groupSeed);
        float fade=pow(max(0.,1-age/tail),1.8)*max(lane,event);
        float tick=floor(u.time*1.8+groupSeed*7);
        float symbol=hash21(float2(col*7+row,tick));
        float mask=glyph(fract(g),symbol), headLight=exp(-age*1.4);
        float3 tint=mix(ink(.05,u.palette),mix(ink(1,u.palette),float3(1),.32),headLight);
        c+=tint*mask*fade*(.21+k*.23+headLight*.65+u.high*step(.86,seed)*.4);
    }
    return c*u.intensity;
}
// Repeated shear preserves continuous flow. Five translucent glass ribbons overlap.
float3 plasmaV2(float2 p, thread const Uniforms &u) {
    float t=u.time*.09+u.phase, tension=.15+u.bass*.025;
    float2 q=turn(p,-.25);
    for(int i=0;i<3;i++) {
        float k=float(i);
        q.x+=sin(q.y*(1.8+k*.4)+t*(.4+k*.1))*(.18+u.mid*.055);
        q.y+=sin(q.x*(1.4+k*.35)-t*.5+k)*.19;
    }
    float3 c=ink(0,u.palette)*.006;
    for(int i=0;i<5;i++) {
        float k=float(i), center=(k-2)*.38+.10*sin(q.x*1.3+t*.3+k);
        float d=(q.y-center)/tension, a=abs(d);
        float mask=1-smoothstep(.95,1.02,a);
        float face=sqrt(max(0.,1-d*d));
        float folds=.5+.5*sin(d*8+q.x*1.4-t*.5+k);
        float edge=exp(-abs(a-.93)*65);
        float spec=pow(max(0.,face*.75+d*.55),18);
        float3 tint=ink(.18+.13*k,u.palette);
        float3 sheet=tint*(.055+.18*face+.045*folds);
        sheet+=mix(tint,float3(1,.96,.88),.55)*(spec*.48+edge*(.17+u.high*.09));
        float filament=pow(.5+.5*cos(d*47+q.x*3),50)*u.high*.045;
        sheet+=tint*filament;
        sheet+=ink(1,u.palette)*edge*u.transient*exp(-pow(q.x-.4*sin(t),2)*5)*.38;
        c=mix(c,c*.35+sheet,mask*.87);
    }
    return c*u.intensity;
}
#define outrunScene outrunV2
#define crystalScene crystalV2
#define galaxyScene galaxyV2
#define rainScene rainV2
#define plasmaScene plasmaV2
#endif

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
