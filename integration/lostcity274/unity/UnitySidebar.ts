import Component from '#/cache/config/Component.js';
import ObjType from '#/cache/config/ObjType.js';
import {interfaceActive,interfaceText} from './UnityInterface.js';
export function itemGraphic(id:number,count:number){const obj=ObjType.get(id);let variant=id;for(let i=0;i<(obj.countobj?.length??0);i++)if(obj.countco?.[i]&&count>=obj.countco[i])variant=obj.countobj![i];return 'item-'+variant;}
export function originalSidebar(p:any,s:any){
 const root=p.modalSide>=0?p.modalSide:p.tabs[s.activeTab];if(root<0)return null;
 const signed=(v:number)=>v>32767?v-65536:v;
 function node(id:number,x=0,y=0):any{const c=Component.get(id);if(!c||s.hidden.get(id)===true)return null;const active=interfaceActive(p,c);
  const n:any={id,type:c.comType,x,y,width:c.width,height:c.height,scroll:c.scroll,hidden:c.hide&&!s.hidden.has(id),over:c.overLayer,button:c.buttonType,active,font:c.font,center:c.center,shadow:c.shadowed,fill:c.fill,alpha:c.trans,colour:s.colours.get(id)??(active?c.activeColour:c.colour),overColour:active?c.activeOverColour:c.overColour,text:interfaceText(p,c,s.text.get(id)??(active&&c.activeText?c.activeText:c.text)??''),graphic:(active?c.activeGraphic:c.graphic)?.replace(',','-')??'',option:c.option??c.action??'',clientCode:c.clientCode};
  if(c.comType===6){const reward=s.interfaceObjects.get(id);if(reward){n.type=5;n.graphic=itemGraphic(reward.obj,50);n.x+=(c.width-32)/2;n.y+=(c.height-32)/2;}else n.graphic=(active&&c.activeModel>0||c.model>0)?'model-'+id+'-'+(active&&c.activeModel>0?1:0):'';}
  if(c.comType===0)n.children=Array.from(c.childId??[],(child,i)=>node(child,signed(c.childX![i]),signed(c.childY![i]))).filter(Boolean);
  if(c.comType===2){n.marginX=c.marginX;n.marginY=c.marginY;n.slotX=Array.from(c.inventorySlotOffsetX??[],signed);n.slotY=Array.from(c.inventorySlotOffsetY??[],signed);n.slotGraphics=Array.from(c.inventorySlotGraphic??[],g=>g?.replace(',','-')??'');}
  return n;
 }return {root,node:node(root)};
}
