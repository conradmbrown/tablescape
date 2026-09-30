import fs from 'node:fs';
import path from 'node:path';
import Jagfile from '#/io/Jagfile.js';
import FileStream from '#/io/FileStream.js';
const root=path.resolve('../..'),out=path.join(root,'Saved/audio-cache/source');fs.mkdirSync(out,{recursive:true});
const sounds=Jagfile.load('data/pack/client/sounds').read('sounds.dat')??Jagfile.load('data/pack/client/sounds').read('wave.dat');
if(!sounds)throw Error('Original sound bank missing');fs.writeFileSync(path.join(out,'sounds.dat'),sounds.data);
const cache=new FileStream('data/pack',false,true);let count=0;
for(let id=0;id<cache.count(3);id++){const midi=cache.read(3,id,true);if(midi){fs.writeFileSync(path.join(out,`${id}.mid`),midi);count++;}}
cache.close();console.log('Original media extracted: midi='+count);
