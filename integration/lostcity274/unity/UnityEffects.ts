import Player from '#/engine/entity/Player.js';
import Npc from '#/engine/entity/Npc.js';
import Zone from '#/engine/zone/Zone.js';
import World from '#/engine/World.js';
import SpotanimType from '#/cache/config/SpotanimType.js';
import SeqType from '#/cache/config/SeqType.js';
import {sequence} from './UnityAnimation.js';
import {groundHeight} from './UnityTerrain.js';
let serial=0,installed=false;const attached=new WeakMap<object,any[]>();let worldEffects:any[]=[];
export function effectDefinition(id:number){const t=SpotanimType.get(id);if(!t)return null;return {type:id,model:t.model,sequence:t.anim,scaleH:t.resizeh/128,scaleV:t.resizev/128,angle:t.angle,sequenceData:t.anim>=0?sequence(t.anim):null,recolS:Array.from(t.recol_s),recolD:Array.from(t.recol_d),duration:Math.max(.1,(SeqType.get(t.anim)?.duration??30)/50)};}
export function installEffects(){
 if(installed)return;installed=true;
 for(const proto of [Player.prototype,Npc.prototype]){const original=proto.spotanim;proto.spotanim=function(id:number,height:number,delay:number){original.call(this as any,id,height,delay);const definition=effectDefinition(id);if(!definition)return;const list=(attached.get(this)??[]).filter(e=>World.currentTick-e.tick<12);list.push({...definition,event:++serial,tick:World.currentTick,kind:'attached',height:height/128,delay:delay/50});attached.set(this,list.slice(-8));};}
 const anim=Zone.prototype.animMap;Zone.prototype.animMap=function(x,z,id,height,delay){anim.call(this,x,z,id,height,delay);const definition=effectDefinition(id);if(definition)record({...definition,kind:'ground',level:this.level,x:x+.5,z:z+.5,y:groundHeight(x+.5,z+.5,this.level)+height/128,delay:delay/50});};
 const projectile=Zone.prototype.mapProjAnim;Zone.prototype.mapProjAnim=function(x,z,dstX,dstZ,target,id,srcHeight,dstHeight,startDelay,endDelay,peak,arc){projectile.call(this,x,z,dstX,dstZ,target,id,srcHeight,dstHeight,startDelay,endDelay,peak,arc);const definition=effectDefinition(id);if(definition)record({...definition,kind:'projectile',level:this.level,x:x+.5,z:z+.5,y:groundHeight(x+.5,z+.5,this.level)+srcHeight*4/128,dstX:dstX+.5,dstZ:dstZ+.5,dstY:groundHeight(dstX+.5,dstZ+.5,this.level)+dstHeight*4/128,target,dstHeight:dstHeight*4/128,delay:startDelay/50,duration:(endDelay-startDelay+1)/50,peak,arc:arc/128});};
}
function record(event:any){worldEffects=worldEffects.filter(e=>World.currentTick-e.tick<12);worldEffects.push({...event,event:++serial,tick:World.currentTick});worldEffects=worldEffects.slice(-512);}
export function actorEffects(entity:Player|Npc){return {effects:(attached.get(entity)??[]).filter(e=>World.currentTick-e.tick<12)};}
export function nearbyEffects(p:Player){return worldEffects.filter(e=>e.level===p.level&&World.currentTick-e.tick<12&&Math.abs(e.x-p.x)<32&&Math.abs(e.z-p.z)<32);}
