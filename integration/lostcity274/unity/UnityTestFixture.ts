import fs from 'node:fs';
import path from 'node:path';
import Player from '#/engine/entity/Player.js';
import InvType from '#/cache/config/InvType.js';
import ObjType from '#/cache/config/ObjType.js';

// Opt-in local QA setup. No HTTP action can create a fixture or grant privileges.
// Only brand-new, randomly named QA characters can consume a one-shot file.
export function readTestFixture(username:string):any|null {
    const dir=process.env.SCAPE_TEST_FIXTURE_DIR;
    if(!dir||!/^unityqa[0-9a-f]{5}$/.test(username))return null;
    if(fs.existsSync(`data/players/main/${username}.sav`))throw Error('QA fixtures require a new character');
    const file=path.join(dir,username+'.json');
    if(!fs.existsSync(file))return null;
    if(fs.statSync(file).size>16384)throw Error('QA fixture too large');
    const f=JSON.parse(fs.readFileSync(file,'utf8'));
    if(!Array.isArray(f.spawn)||f.spawn.length!==3||f.spawn.some((n:number)=>!Number.isInteger(n)||n<0||n>16383)||f.spawn[2]>3)throw Error('Invalid QA spawn');
    for(const [stat,level] of Object.entries(f.levels??{}))if(!/^\d+$/.test(stat)||Number(stat)>20||!Number.isInteger(level)||Number(level)<1||Number(level)>99)throw Error('Invalid QA level');
    for(const [stat,current] of Object.entries(f.currentLevels??{}))if(!/^\d+$/.test(stat)||Number(stat)>20||!Number.isInteger(current)||Number(current)<1||Number(current)>Number(f.levels?.[stat]??(stat==='3'?10:1)))throw Error('Invalid QA current level');
    for(const item of f.items??[])if(ObjType.getId(item.name)<0||!Number.isInteger(item.count)||item.count<1||item.count>100000)throw Error('Invalid QA item '+item.name);
    fs.unlinkSync(file);return f;
}
export function applyTestFixture(player:Player,f:any) {
    if(!f)return;
    const inv=InvType.getId('inv');player.invClear(inv);
    for(const [stat,level] of Object.entries(f.levels??{}))player.setLevel(Number(stat),Number(level));
    for(const [stat,current] of Object.entries(f.currentLevels??{}))player.levels[Number(stat)]=Number(current);
    for(const item of f.items??[])player.invAdd(inv,ObjType.getId(item.name),item.count);
    player.teleport(f.spawn[0],f.spawn[1],f.spawn[2]);
    player.messageGame('Disposable QA fixture: supplied starting items and levels; subsequent actions use normal gameplay.');
}
