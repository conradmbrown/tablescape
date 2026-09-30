import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
const root=path.resolve(new URL('..',import.meta.url).pathname),cache=path.join(root,'Saved/audio-cache'),source=path.join(cache,'source');
fs.mkdirSync(cache,{recursive:true});const [mode,idText,loopsText='1']=process.argv.slice(2);const id=Number(idText),loops=Number(loopsText);
if(mode==='prepare'){
 const require=createRequire(path.join(root,'vendor/lostcity-engine274/package.json'));const esbuild=require('esbuild');const client=path.join(root,'vendor/lostcity-client274');
 await esbuild.build({stdin:{contents:`export {default as JagFX} from '${client}/src/sound/JagFX.ts'; export {default as Packet} from '${client}/src/io/Packet.ts';`,resolveDir:client},outfile:path.join(cache,'jagfx.mjs'),bundle:true,platform:'node',format:'esm',tsconfigRaw:{compilerOptions:{baseUrl:client,paths:{'#/*':['src/*']}}}});
 const {JagFX,Packet}=await import(pathToFileURL(path.join(cache,'jagfx.mjs')));JagFX.init(new Packet(fs.readFileSync(path.join(source,'sounds.dat'))));
 const delays={};let count=0;for(let i=0;i<JagFX.synth.length;i++)if(JagFX.synth[i]){delays[i]=JagFX.delays[i];count++;}fs.writeFileSync(path.join(cache,'sound-delays.json'),JSON.stringify(delays));console.log('Original sound definitions: '+count);process.exit(0);
}
if(!Number.isInteger(id)||id<0||id>65535||!Number.isInteger(loops)||loops<1||loops>8)throw Error('Invalid audio key');
const output=path.join(cache,`${mode}-${id}-${loops}.wav`);if(fs.existsSync(output))process.exit(0);
let wave;
if(mode==='sound'){
 const {JagFX,Packet}=await import(pathToFileURL(path.join(cache,'jagfx.mjs')));JagFX.init(new Packet(fs.readFileSync(path.join(source,'sounds.dat'))));const result=JagFX.generate(id,loops);if(!result)throw Error('Unknown original sound');wave=Buffer.from(result.data.subarray(0,result.pos));
}else if(mode==='music'){
 const folder=path.join(root,'vendor/lostcity-client274/src/3rdparty/tinymidipcm');const {default:load}=await import(pathToFileURL(path.join(folder,'tinymidipcm.mjs')));
 const m=await load({wasmBinary:fs.readFileSync(path.join(folder,'tinymidipcm.wasm'))});
 const font=fs.readFileSync(path.join(root,'vendor/lostcity-engine274/public/client/SCC1_Florestan.sf2')),midi=fs.readFileSync(path.join(source,`${id}.mid`));
 const fp=m._malloc(font.length);m.HEAPU8.set(font,fp);const sf=m._tsf_load_memory(fp,font.length);if(!sf)throw Error('Original soundfont failed');m._tsf_set_output(sf,0,22050,0);m._tsf_channel_set_bank_preset(sf,9,128,0);
 const mp=m._malloc(midi.length);m.HEAPU8.set(midi,mp);let next=m._tml_load_memory(mp,midi.length);if(!next)throw Error('Invalid original MIDI');
 const size=102400,bp=m._malloc(size),tp=m._malloc(8);m.setValue(tp,0,'double');const blocks=[];let bytes=0;
 do{next=m._midi_render(sf,next,2,22050,bp,size,tp);const floats=new Float32Array(m.HEAPU8.buffer,bp,size/4),pcm=Buffer.alloc(floats.length*2);for(let i=0;i<floats.length;i++)pcm.writeInt16LE(Math.round(Math.max(-1,Math.min(1,floats[i]))*32767),i*2);blocks.push(pcm);bytes+=pcm.length;if(bytes>22050*4*600)throw Error('MIDI exceeds ten minutes');}while(next);
 const header=Buffer.alloc(44);header.write('RIFF');header.writeUInt32LE(bytes+36,4);header.write('WAVEfmt ',8);header.writeUInt32LE(16,16);header.writeUInt16LE(1,20);header.writeUInt16LE(2,22);header.writeUInt32LE(22050,24);header.writeUInt32LE(88200,28);header.writeUInt16LE(4,32);header.writeUInt16LE(16,34);header.write('data',36);header.writeUInt32LE(bytes,40);wave=Buffer.concat([header,...blocks]);
}else throw Error('Unknown media kind');
fs.writeFileSync(output+'.tmp',wave);fs.renameSync(output+'.tmp',output);console.log(`${mode} ${id}: ${wave.length} bytes`);
