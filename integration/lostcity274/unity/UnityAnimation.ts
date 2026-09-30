import ObjType from '#/cache/config/ObjType.js';
import SeqType from '#/cache/config/SeqType.js';
import AnimFrame from '#/cache/graphics/AnimFrame.js';
import AnimBase from '#/cache/graphics/AnimBase.js';
export function sequence(id:number){
    const seq=SeqType.get(id);if(!seq)throw Error('Unknown sequence');
    const held=(value:number,gender:number)=>{if(value<512)return null;const t=ObjType.get(value-512);return {models:(gender===0?[t.manwear,t.manwear2,t.manwear3]:[t.womanwear,t.womanwear2,t.womanwear3]).filter(x=>x>=0),recolS:Array.from(t.recol_s??[]),recolD:Array.from(t.recol_d??[]),offsetY:(gender===0?t.manwearOffset:t.womanwearOffset)/128};};
    return {id,loops:seq.loops,maxloops:seq.maxloops,duplicatebehaviour:seq.duplicatebehaviour,postanim_move:seq.postanim_move,replaceheldleft:seq.replaceheldleft,replaceheldright:seq.replaceheldright,leftMale:held(seq.replaceheldleft,0),leftFemale:held(seq.replaceheldleft,1),rightMale:held(seq.replaceheldright,0),rightFemale:held(seq.replaceheldright,1),frames:Array.from(seq.frames??[]).map((frameId,i)=>{
        const f=AnimFrame.instances[frameId];if(!f)return {delay:1,transforms:[]};const b=AnimBase.instances[f.base];
        return {delay:seq.delay?.[i]||f.delay||1,transforms:Array.from(f.groups).map((g,k)=>({type:b.types[g],labels:Array.from(b.labels[g]),x:f.x[k],y:f.y[k],z:f.z[k]}))};
    })};
}
