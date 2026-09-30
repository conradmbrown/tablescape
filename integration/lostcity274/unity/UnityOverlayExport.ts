import fs from 'node:fs';
import path from 'node:path';
import Jagfile from '#/io/Jagfile.js';
const out=path.resolve('../../Saved/overlay-source');fs.mkdirSync(out,{recursive:true});
const title=Jagfile.load('data/pack/client/title');
for(const name of ['index.dat','p11_full.dat','p12_full.dat','b12_full.dat','q8_full.dat']){const file=title.read(name);if(!file)throw Error('Missing original font '+name);fs.writeFileSync(path.join(out,name),file.data);}

const media=Jagfile.load('data/pack/client/media');
const config=Jagfile.load('data/pack/client/config');
for(const name of ['obj.dat','obj.idx'])fs.writeFileSync(path.join(out,name),config.read(name)!.data);
import Component from '#/cache/config/Component.js';
Component.load('data/pack');const graphics=new Set<string>();
for(const c of (Component as any).components)if(c){for(const g of [c.graphic,c.activeGraphic,...(c.inventorySlotGraphic??[])])if(g)graphics.add(g);}
for(let i=0;i<13;i++)graphics.add('sideicons,'+i);
for(const name of ['invback','backhmid2','backhmid1','backbase2','backright2','backleft2','backvmid2','backvmid3','redstone1','redstone2','redstone3','scrollbar'])graphics.add(name+',0');graphics.add('scrollbar,1');
fs.mkdirSync(path.join(out,'media'),{recursive:true});
for(const name of new Set(['index',...Array.from(graphics,g=>g.split(',')[0])])){const file=media.read(name+'.dat');if(!file)throw Error('Missing original sprite bank '+name);fs.writeFileSync(path.join(out,'media',name+'.dat'),file.data);}
fs.writeFileSync(path.join(out,'graphics.json'),JSON.stringify(Array.from(graphics)));

fs.writeFileSync(path.join(out,'component-models.json'),JSON.stringify((Component as any).components.filter((c:any)=>c?.comType===6).flatMap((c:any)=>[0,1].filter(a=>(a?c.activeModel:c.model)>0).map(a=>({id:c.id,active:a,model:a?c.activeModel:c.model,x:256,y:167,width:0,height:0,xan:c.xan,yan:c.yan,zoom:c.zoom,recolS:[],recolD:[]})))));

// Item models use this palette/texel bank too (e.g. cut log ends).
const textures=Jagfile.load('data/pack/client/textures');
fs.mkdirSync(path.join(out,'textures'),{recursive:true});
for(const name of ['index',...Array.from({length:50},(_,i)=>String(i))]){const file=textures.read(name+'.dat');if(file)fs.writeFileSync(path.join(out,'textures',name+'.dat'),file.data);}
