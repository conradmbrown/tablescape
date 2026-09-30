import fs from 'node:fs';
import { unzipSync } from 'fflate';
import Packet from '#/io/Packet.js';
import FloType from '#/cache/config/FloType.js';
import Ground from './Ground.js';
const entries=unzipSync(fs.readFileSync('data/pack/.cache/maps-server.zip'));
type Tile={h:number,under:number,over:number,shape:number,rotation:number,flags:number};
const maps=new Map<string,Tile[]>();
function noise(x:number,z:number){const n=x+z*57,v=BigInt((n<<13)^n);return Number(((v*(v*v*15731n+789221n)+1376312589n)&0x7fffffffn)>>19n)&255;}
function smooth(x:number,z:number){return ((noise(x-1,z-1)+noise(x+1,z-1)+noise(x-1,z+1)+noise(x+1,z+1))/16|0)+((noise(x-1,z)+noise(x+1,z)+noise(x,z-1)+noise(x,z+1))/8|0)+(noise(x,z)/4|0);}
function interpolate(a:number,b:number,x:number,scale:number){const f=(65536-(Math.cos((x*1024/scale|0)*Math.PI/1024)*65536|0))>>1;return ((a*(65536-f))>>16)+((b*f)>>16);}
function octave(x:number,z:number,scale:number){const ix=x/scale|0,iz=z/scale|0,fx=x&(scale-1),fz=z&(scale-1);return interpolate(interpolate(smooth(ix,iz),smooth(ix+1,iz),fx,scale),interpolate(smooth(ix,iz+1),smooth(ix+1,iz+1),fx,scale),fz,scale);}
function height(x:number,z:number){x+=932731;z+=556238;const v=octave(x+45365,z+91923,4)+((octave(x+10294,z+37821,2)-128)>>1)+((octave(x,z,1)-128)>>2)-128;return -Math.max(10,Math.min(60,(v*.3|0)+35))*8;}
function tile(x:number,z:number,level:number):Tile {
 const mx=x>>6,mz=z>>6,key=`m${mx}_${mz}`;
 if(!maps.has(key)){
  const bytes=entries[key];if(!bytes)return {h:0,under:0,over:0,shape:0,rotation:0,flags:0};const p=new Packet(bytes),data:Tile[]=[];
  for(let l=0;l<4;l++)for(let a=0;a<64;a++)for(let b=0;b<64;b++){
   const t={h:0,under:0,over:0,shape:0,rotation:0,flags:0};const i=l*4096+a*64+b;
   while(true){const code=p.g1();if(code===0){t.h=l===0?height(mx*64+a,mz*64+b):data[i-4096].h-240;break;}if(code===1){let h=p.g1();if(h===1)h=0;t.h=(l===0?0:data[i-4096].h)-h*8;break;}if(code<=49){t.over=p.g1();t.shape=(code-2)/4|0;t.rotation=(code-2)&3;}else if(code>81)t.under=code-81;else t.flags=code-49;}
   data.push(t);
  }maps.set(key,data);
 }
 return maps.get(key)![level*4096+(x&63)*64+(z&63)];
}
export function mapSource(name:string){return entries[name];}
export function tileFlags(x:number,z:number,level:number){return tile(x,z,level).flags;}
export function groundHeight(x:number,z:number,level:number){
 const a=Math.floor(x),b=Math.floor(z),u=x-a,v=z-b;
 return -((tile(a,b,level).h*(1-u)+tile(a+1,b,level).h*u)*(1-v)+(tile(a,b+1,level).h*(1-u)+tile(a+1,b+1,level).h*u)*v)/128;
}
let floorsReady=false;
const hslCache=new Map<number,{h:number,s:number,l:number,chroma:number,weighted:number}>();
function floorHsl(rgb:number){
 let entry=hslCache.get(rgb);if(entry)return entry;
 const r=((rgb>>16)&255)/256,g=((rgb>>8)&255)/256,b=(rgb&255)/256,min=Math.min(r,g,b),max=Math.max(r,g,b),l=(min+max)/2;
 let h=0,s=0;if(max!==min){s=l<.5?(max-min)/(max+min):(max-min)/(2-max-min);h=(max===r?(g-b)/(max-min):max===g?(b-r)/(max-min)+2:(r-g)/(max-min)+4)/6;}
 const chroma=Math.max(1,Math.trunc((l>.5?1-l:l)*s*512));entry={h:Math.trunc(h*256),s:Math.trunc(s*256),l:Math.trunc(l*256),chroma,weighted:Math.trunc(h*chroma)};hslCache.set(rgb,entry);return entry;
}
function pack(h:number,s:number,l:number){if(l>179)s>>=1;if(l>192)s>>=1;if(l>217)s>>=1;if(l>243)s>>=1;return ((h>>2)<<10)+((s>>5)<<7)+(l>>1);}
function blend(x:number,z:number,level:number){let hue=0,sat=0,light=0,chroma=0,count=0;
 for(let a=x-4;a<=x+5;a++)for(let b=z-4;b<=z+5;b++){const under=tile(a,b,level).under;if(!under)continue;const f=floorHsl(FloType.get(under-1).rgb);hue+=f.weighted;sat+=f.s;light+=f.l;chroma+=f.chroma;count++;}
 return count&&chroma?pack(Math.trunc(hue*256/chroma),Math.trunc(sat/count),Math.trunc(light/count)):-1;
}
function light(x:number,z:number,level:number){const dx=tile(x+1,z,level).h-tile(x-1,z,level).h,dz=tile(x,z+1,level).h-tile(x,z-1,level).h;const len=Math.trunc(Math.sqrt(dx*dx+65536+dz*dz));return 96+Math.trunc((-50*Math.trunc(dx*256/len)-10*Math.trunc(65536/len)-50*Math.trunc(dz*256/len))/213);}
function shade(hsl:number,brightness:number){if(hsl===-2||hsl===-1)return 12345678;return (hsl&0xff80)+Math.max(2,Math.min(126,Math.trunc(brightness*(hsl&127)/128)));}
const colours=new Map<number,number[]>();
function palette(packed:number){let c=colours.get(packed);if(c)return c;const h=(packed>>10)/64+1/128,s=((packed>>7)&7)/8+1/16,l=(packed&127)/128;const q=l<.5?l*(1+s):l+s-l*s,p=2*l-q;
 const hue=(t:number)=>{t=(t+1)%1;const v=t<1/6?p+(q-p)*6*t:t<.5?q:t<2/3?p+(q-p)*(2/3-t)*6:p;return Math.round(Math.pow(v,.8)*255)/255;};c=[hue(h+1/3),hue(h),hue(h-1/3)];colours.set(packed,c);return c;
}
export function terrain(x:number,z:number,level:number,size=40){
 if(!floorsReady){FloType.load('data/pack');floorsReady=true;}
 const groups=new Map<number,{texture:number,vertices:number[],colours:number[],uv:number[]}>();
 const startX=size===40?x-16:x,startZ=size===40?z-16:z;
 for(let a=startX;a<startX+size;a++)for(let b=startZ;b<startZ+size;b++){
  const t=tile(a,b,level),under=t.under?FloType.get(t.under-1):null,over=t.over?FloType.get(t.over-1):null;if(!under&&!over)continue;
  const texture=over?.texture??-1,c=under?blend(a,b,level):-1,o=over?floorHsl(over.rgb):null,d=o?pack(o.h,o.s,o.l):-2;
  const lights=[light(a,b,level),light(a+1,b,level),light(a+1,b+1,level),light(a,b+1,level)];
  const uc=lights.map(l=>shade(c,l)),oc=lights.map(l=>texture>=0?Math.max(0,Math.min(127,l)):over?.rgb===0xff00ff?12345678:shade(d,l));
  const g=new Ground(a,b,over?t.shape+1:0,t.rotation,texture,t.h,tile(a+1,b,level).h,tile(a+1,b+1,level).h,tile(a,b+1,level).h,uc[0],uc[1],uc[2],uc[3],oc[0],oc[1],oc[2],oc[3],d,c);
  for(let i=0;i<g.faceVertexA.length;i++){
   const tex=g.faceTexture?.[i]??-1;if(tex<0&&g.faceColourA[i]===12345678)continue;
   if(!groups.has(tex))groups.set(tex,{texture:tex,vertices:[],colours:[],uv:[]});const batch=groups.get(tex)!;
   const indices=[g.faceVertexA[i],g.faceVertexC[i],g.faceVertexB[i]],face=[g.faceColourA[i],g.faceColourC[i],g.faceColourB[i]];
   for(let j=0;j<3;j++){const v=indices[j];batch.vertices.push(g.vertexX[v]/128,-g.vertexY[v]/128,g.vertexZ[v]/128);
    const col=tex>=0?Array(3).fill(Math.max(.15,Math.min(1,face[j]/96))):palette(face[j]);batch.colours.push(...col);
    batch.uv.push(g.vertexX[v]/128,1-g.vertexZ[v]/128);
   }
  }
 }
 return {revision:274,x,z,level,meshes:[...groups.values()]};
}
