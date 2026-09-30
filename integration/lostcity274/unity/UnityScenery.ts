import Packet from '#/io/Packet.js';
import LocType from '#/cache/config/LocType.js';
import {groundHeight,mapSource,tileFlags} from './UnityTerrain.js';
type Placement={id:number,x:number,z:number,level:number,shape:number,angle:number};
const squares=new Map<string,Placement[]>();
const array=(a:ArrayLike<number>|null)=>a?Array.from(a):[];
export function scenery(id:number,x:number,z:number,level:number,shape:number,angle:number){
 const t=LocType.get(id);if(!t)return null;
 const modelShape=shape===11?10:shape>=4&&shape<=8?4:shape;
 const models=array(t.models).filter((_,i)=>t.shapes?t.shapes[i]===modelShape:modelShape===10);
 if(!models.length)return null;
 const recolS=array(t.recol_s),recolD=array(t.recol_d);
 const parts:{models:number[],recolS:number[],recolD:number[],mirror:boolean,yaw:number,modelOffsetX?:number,modelOffsetZ?:number}[]=[{models,recolS,recolD,mirror:shape===2?!t.mirror:t.mirror,yaw:0}];
 if(shape===2)parts.push({models,recolS,recolD,mirror:t.mirror,yaw:90});
 // World.setDecor's diagonal faces use distinct rotations and offsets in cache
 // units. Keep both shape-8 faces; Unity's depth buffer resolves wall occlusion.
 if(shape>=6&&shape<=8){
  parts.length=0;
  if(shape!==7)parts.push({models,recolS,recolD,mirror:t.mirror,yaw:45,modelOffsetX:53/128,modelOffsetZ:-53/128});
  if(shape!==6)parts.push({models,recolS,recolD,mirror:t.mirror,yaw:225,modelOffsetX:-45/128,modelOffsetZ:45/128});
 }
 const large=shape===10||shape===11;
 let decorX=0,decorZ=0;
 if(shape===5){const wall=loadSquare(x>>6,z>>6).filter(p=>p.x===x&&p.z===z&&p.level===level&&p.shape<4).at(-1);const width=wall?LocType.get(wall.id).wallwidth:16;decorX=[1,0,-1,0][angle]*width/128;decorZ=[0,-1,0,1][angle]*width/128;}
 const hillHeights=t.hillskew?[groundHeight(x,z,level),groundHeight(x+1,z,level),groundHeight(x+1,z+1,level),groundHeight(x,z+1,level)].map(h=>Math.round(-h*128)):[];
 return {lightAmbient:64+(t.ambient&255),lightContrast:768+(t.contrast&255)*5,hillHeights,id,key:`${x}:${z}:${shape}:${id}`,x,z,y:groundHeight(x+.5,z+.5,level),angle,shape,name:t.name??'Scenery',description:t.desc??'',models,parts,recolS,recolD,ops:(t.op??[]).map(o=>o==='hidden'?'':o??''),width:large?t.width:1,length:large?t.length:1,scaleX:t.resizex/128,scaleY:t.resizey/128,scaleZ:t.resizez/128,offsetX:t.offsetx/128+decorX,offsetY:t.offsety/128,offsetZ:t.offsetz/128+decorZ};
}
export function staticScenery(x:number,z:number,level:number,size:number){
 const result:any[]=[];
 for(let mx=x>>6;mx<=(x+size-1)>>6;mx++)for(let mz=z>>6;mz<=(z+size-1)>>6;mz++){
  for(const p of loadSquare(mx,mz))if(p.level===level&&p.x>=x&&p.x<x+size&&p.z>=z&&p.z<z+size){
   const type=LocType.get(p.id);if(!type||type.active)continue; // Interactive/dynamic scenery comes from authoritative world state.
   const render=scenery(p.id,p.x,p.z,p.level,p.shape,p.angle);if(render)result.push(render);
  }
 }
 return result;
}

function loadSquare(mx:number,mz:number){
  const key=`l${mx}_${mz}`;
  if(!squares.has(key)){
   const data=mapSource(key),locs:Placement[]=[];if(data){const packet=new Packet(data);let id=-1;
    for(let delta=packet.gsmarts();delta!==0;delta=packet.gsmarts()){
     id+=delta;let coord=0;for(let dc=packet.gsmarts();dc!==0;dc=packet.gsmarts()){
      coord+=dc-1;const info=packet.g1(),px=mx*64+((coord>>6)&63),pz=mz*64+(coord&63),plane=coord>>12;
      const bridged=(tileFlags(px,pz,1)&2)!==0;locs.push({id,x:px,z:pz,level:plane-(bridged?1:0),shape:info>>2,angle:info&3});
     }
    }
   }squares.set(key,locs);
  }
return squares.get(key)!;
}
