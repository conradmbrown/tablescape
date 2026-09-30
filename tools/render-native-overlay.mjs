import fs from 'node:fs';import path from 'node:path';import zlib from 'node:zlib';import {pathToFileURL} from 'node:url';
export function png(width,height,rgba){const crc=b=>{let c=0xffffffff;for(const n of b){c^=n;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;};const chunk=(type,data)=>{const body=Buffer.concat([Buffer.from(type),data]),out=Buffer.alloc(body.length+8);out.writeUInt32BE(data.length);body.copy(out,4);out.writeUInt32BE(crc(body),body.length+4);return out;};const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=6;const rows=Buffer.alloc(height*(width*4+1));for(let y=0;y<height;y++)rgba.copy(rows,y*(width*4+1)+1,y*width*4,(y+1)*width*4);return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]);}
let runtime;
export async function renderOverlayModel(def,root){
 if(!runtime){runtime=await import(pathToFileURL(path.join(root,'Saved/overlay-cache/original-renderer.mjs')));runtime.Pix3D.initColourTable(.8);}
 const {Model,Pix2D,Pix3D}=runtime;Model.unpack(def.model,fs.readFileSync(path.join(root,'Unity/Assets/LostCity274/models',def.model+'.ob2')));const model=Model.load(def.model);if(!model)throw Error('Original interface model missing');
 for(let i=0;i<(def.recolS?.length??0);i++)model.recolour(def.recolS[i],def.recolD[i]);model.calculateNormals(64,768,-50,-10,-50,true);
 const pixels=new Int32Array(512*334);Pix2D.setPixels(pixels,512,334);Pix3D.setClipping(512,334);Pix3D.originX=def.x+(def.width>>1);Pix3D.originY=def.y+(def.height>>1);
 model.objRender(0,def.yan,0,def.xan,0,(Pix3D.sinTable[def.xan]*def.zoom)>>16,(Pix3D.cosTable[def.xan]*def.zoom)>>16);
 const rgba=Buffer.alloc(pixels.length*4);for(let i=0;i<pixels.length;i++){const c=pixels[i];if(c){rgba[i*4]=c>>16&255;rgba[i*4+1]=c>>8&255;rgba[i*4+2]=c&255;rgba[i*4+3]=255;}}
 return png(512,334,rgba);
}
// Trim transparent borders for imported UI model icons; retain the original draw offset.
export function cropPng(bytes){const w=bytes.readUInt32BE(16),h=bytes.readUInt32BE(20),rows=zlib.inflateSync(bytes.subarray(41,41+bytes.readUInt32BE(33)));let left=w,top=h,right=-1,bottom=-1;for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(rows[y*(w*4+1)+1+x*4+3]){left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x);bottom=Math.max(bottom,y);}if(right<0)return {bytes:png(1,1,Buffer.alloc(4)),x:0,y:0};const width=right-left+1,height=bottom-top+1,rgba=Buffer.alloc(width*height*4);for(let y=0;y<height;y++)rows.copy(rgba,y*width*4,(top+y)*(w*4+1)+1+left*4,(top+y)*(w*4+1)+1+(right+1)*4);return {bytes:png(width,height,rgba),x:left,y:top};}
