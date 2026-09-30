import Component from '#/cache/config/Component.js';
import ObjType from '#/cache/config/ObjType.js';
import path from 'node:path';import fs from 'node:fs';import {createHash} from 'node:crypto';import {pathToFileURL} from 'node:url';
const root=path.resolve('../..');const cache=path.join(root,'Saved/overlay-cache');
export function originalOverlay(p:any,s:any,text:(c:any)=>string){
 const main=Component.get(p.modalMain);if(!main||!(main.comName??'').split(':')[0].startsWith('questscroll'))return null;
 const nodes:any[]=[];function visit(c:any,x:number,y:number){if(!c||s.hidden.get(c.id)===true||(c.hide&&!s.hidden.has(c.id)))return;
  if(c.comType===0){for(let i=0;i<(c.childId?.length??0);i++){const signed=(v:number)=>v>32767?v-65536:v;visit(Component.get(c.childId[i]),x+signed(c.childX[i]),y+signed(c.childY[i]));}return;}
  if(c.comType!==4&&c.comType!==6)return;
  const n:any={id:c.id,type:c.comType,x,y,width:c.width,height:c.height,text:text(c),button:c.buttonType,font:c.font,center:c.center,shadow:c.shadowed,colour:s.colours.get(c.id)??c.colour,overColour:c.overColour??0};
  if(c.comType===6){Object.assign(n,{model:c.model,xan:c.xan,yan:c.yan,zoom:c.zoom,recolS:[],recolD:[]});const reward=s.interfaceObjects.get(c.id);if(reward){const obj=ObjType.get(reward.obj);Object.assign(n,{model:obj.model,xan:obj.xan2d,yan:obj.yan2d,zoom:Math.floor(obj.zoom2d*100/Math.max(1,reward.scale)),recolS:Array.from(obj.recol_s??[]),recolD:Array.from(obj.recol_d??[])});}n.image=createHash('sha256').update(JSON.stringify(n)).digest('hex');}
  nodes.push(n);
 }visit(main,0,0);return {root:p.modalMain,width:512,height:334,nodes};
}
const pending=new Map<string,Promise<Buffer>>();
export async function overlayPng(node:any){const file=path.join(cache,node.image+'.png');if(fs.existsSync(file))return fs.readFileSync(file);if(pending.has(file))return pending.get(file)!;
 const job=(async()=>{const renderer=await import(pathToFileURL(path.join(root,'tools/render-native-overlay.mjs')).href);const bytes=await renderer.renderOverlayModel(node,root);fs.mkdirSync(cache,{recursive:true});fs.writeFileSync(file,bytes);return bytes;})();pending.set(file,job);try{return await job;}finally{pending.delete(file);}
}
