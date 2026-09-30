import Component from '#/cache/config/Component.js';
import NpcType from '#/cache/config/NpcType.js';

// Interface model and animation packets persist per component, just as in revision 274.
// Only expose a portrait when that component belongs to the currently visible chat.
export function dialogueHead(p:any,s:any,playerParts:()=>any[]) {
    if(p.modalChat<0)return null;
    function visit(c:any):any {
        if(!c||s.hidden.get(c.id)===true||(c.hide&&!s.hidden.has(c.id)))return null;
        if(c.comType===0){for(const id of c.childId??[]){const head=visit(Component.get(id));if(head)return head;}return null;}
        const head=s.interfaceHeads.get(c.id);if(c.comType!==6||!head)return null;
        let parts:any[];
        if(head.kind==='npc'){
            const npc=NpcType.get(head.id);
            parts=[{models:Array.from(npc.heads??[]),recolS:Array.from(npc.recol_s??[]),recolD:Array.from(npc.recol_d??[])}];
        }else parts=playerParts();
        parts=parts.filter(part=>part.models.length>0);
        if(!parts.length)return null;
        return {root:p.modalChat,component:c.id,kind:head.kind,npc:head.id??-1,sequence:s.interfaceAnims.get(c.id)??c.anim??-1,xan:c.xan,yan:c.yan,zoom:c.zoom,parts};
    }
    return visit(Component.get(p.modalChat));
}
