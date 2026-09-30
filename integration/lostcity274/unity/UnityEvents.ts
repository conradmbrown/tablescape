import Player from '#/engine/entity/Player.js';
import Npc from '#/engine/entity/Npc.js';
import SeqType from '#/cache/config/SeqType.js';
import NpcType from '#/cache/config/NpcType.js';
import ParamType from '#/cache/config/ParamType.js';
import {ParamHelper} from '#/cache/config/ParamHelper.js';
import World from '#/engine/World.js';
const animations=new WeakMap<object,{anim:number,animTick:number,animDelay:number,animEvent:number,animDeath:boolean,until:number}>();
type Hit={id:number,tick:number,damage:number,type:number,hp:number,maxHp:number};
const hits=new WeakMap<object,Hit[]>();let hitId=0;
let installed=false,animationId=0;
let npcDeaths:any[]=[];
export function recentNpcDeaths(){npcDeaths=npcDeaths.filter(e=>World.currentTick-e.animTick<12);return npcDeaths;}
const deathSequences=new Map<number,number>();
export function deathSequence(entity:Player|Npc){
    if(entity instanceof Player)return SeqType.getId('human_death');
    if(!deathSequences.has(entity.type)){const param=ParamType.get(ParamType.getId('death_anim'));deathSequences.set(entity.type,param?ParamHelper.getIntParam(param.id,NpcType.get(entity.type),param.defaultInt):-1);}
    return deathSequences.get(entity.type)!;
}
export function installEvents(){
    if(installed)return;installed=true;
    // Preserve transient animation updates that the server clears at the end of a tick.
    for(const proto of [Player.prototype,Npc.prototype]){
        const originalDamage=proto.applyDamage;
        proto.applyDamage=function(damage:number,type:number){
            const before=this.levels[3];originalDamage.call(this as any,damage,type);
            const events=(hits.get(this)??[]).filter(h=>World.currentTick-h.tick<12);
            events.push({id:++hitId,tick:World.currentTick,damage:Math.max(0,before-this.levels[3]),type,hp:this.levels[3],maxHp:this.baseLevels[3]});hits.set(this,events.slice(-16));
        };
        const original=proto.playAnimation;
        proto.playAnimation=function(anim:number,delay:number){
            original.call(this as any,anim,delay);
            if(this.animId!==anim)return;
            const seq=anim>=0?SeqType.get(anim):null;
            let duration=seq?.duration??0;
            if(seq&&seq.loops>0&&seq.loops<=seq.frameCount){let tail=0;for(let i=seq.frameCount-seq.loops;i<seq.frameCount;i++)tail+=seq.delay?.[i]||30;duration+=tail*Math.max(0,seq.maxloops-1);}
            const event={anim,animTick:World.currentTick,animDelay:delay,animEvent:++animationId,animDeath:anim>=0&&anim===deathSequence(this as any),until:World.currentTick+Math.ceil((duration+delay)/30)+2};
            animations.set(this,event);
            if(event.animDeath&&this instanceof Npc){npcDeaths.push({...event,id:this.nid,type:this.type,x:this.x,z:this.z,level:this.level});npcDeaths=recentNpcDeaths().slice(-256);console.log('SCAPE_NPC_DEATH_EVENT',this.nid,anim,World.currentTick);}
        };
    }
}
export function animation(entity:Player|Npc){const event=animations.get(entity);return event&&event.until>=World.currentTick?event:{anim:-1,animTick:-1,animDelay:0,animEvent:0,animDeath:false};}

export function combat(entity:Player|Npc){return {hits:(hits.get(entity)??[]).filter(h=>World.currentTick-h.tick<12)};}
