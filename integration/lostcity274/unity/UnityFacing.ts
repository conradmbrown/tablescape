import World from '#/engine/World.js';
import Player from '#/engine/entity/Player.js';
import Npc from '#/engine/entity/Npc.js';

// Export persistent server orientation, not the transient FACE_COORD update mask.
// FACE_ENTITY takes priority, just as it does in the original client's entityFace.
export function facing(entity:Player|Npc){
    const id=entity.faceEntity;
    const target=id>=32768?World.getPlayer(id-32768):id>=0?World.getNpc(id):undefined;
    if(target&&target.level===entity.level){
        return {hasFacing:true,faceX:target.x+target.width/2,faceZ:target.z+target.length/2,
            faceKind:id>=32768?'player':'npc',faceId:id>=32768?id-32768:id};
    }
    return {hasFacing:entity.faceAngleX>=0&&entity.faceAngleZ>=0,
        faceX:entity.faceAngleX/2,faceZ:entity.faceAngleZ/2,faceKind:'',faceId:-1};
}
