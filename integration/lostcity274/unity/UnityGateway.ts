import {dialogueHead} from './UnityDialogue.js';
import {facing} from './UnityFacing.js';
import {originalSidebar,itemGraphic} from './UnitySidebar.js';
import {originalOverlay,overlayPng} from './UnityOverlay.js';
import {installEffects,actorEffects,nearbyEffects} from './UnityEffects.js';
import {audioMessage,audioFile} from './UnityAudio.js';
import {readTestFixture,applyTestFixture} from './UnityTestFixture.js';
import VarPlayerType from '#/cache/config/VarPlayerType.js';
import ScriptProvider from '#/engine/script/ScriptProvider.js';
import ScriptRunner from '#/engine/script/ScriptRunner.js';
import {scenery,staticScenery} from './UnityScenery.js';
import {findPathToLoc} from '#/engine/GameMap.js';
import {CoordGrid} from '#/engine/CoordGrid.js';
import {installEvents,animation,combat,deathSequence,recentNpcDeaths} from './UnityEvents.js';
import {interfaceText,interfaceActive} from './UnityInterface.js';
import {sequence} from './UnityAnimation.js';
import {groundHeight,terrain} from './UnityTerrain.js';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import World from '#/engine/World.js';
import Packet from '#/io/Packet.js';
import ClientSocket from '#/server/ClientSocket.js';
import NullClientSocket from '#/server/NullClientSocket.js';
import { PlayerLoading } from '#/engine/entity/PlayerLoading.js';
import { NetworkPlayer } from '#/engine/entity/NetworkPlayer.js';
import Player from '#/engine/entity/Player.js';
import Component from '#/cache/config/Component.js';
import NpcType from '#/cache/config/NpcType.js';
import LocType from '#/cache/config/LocType.js';
import IdkType from '#/cache/config/IdkType.js';
import ObjType from '#/cache/config/ObjType.js';
import * as rsbuf from '#/network/rsbuf/index.js';

// Private development transport for native Unity. No original client runs.
// Actions are queued as ordinary 274 packets and pass through normal server handlers.
class UnitySocket extends ClientSocket {
    remoteAddress='127.0.0.1';
    send(_data:Uint8Array) {}
    close() { this.state=-1; if(this.player){this.player.requestLogout=true;this.player.client=new NullClientSocket();} }
    terminate() {this.close();}
}
type Session={token:string,player:NetworkPlayer,socket:UnitySocket,touched:number,text:Map<number,string>,hidden:Map<number,boolean>,messages:string[],activeTab:number,tutorialFlash:number,countDialog:boolean,playerOps:string[],audio:any[],music:any,colours:Map<number,number>,interfaceObjects:Map<number,any>,knownNpcs:Map<number,any>,interfaceHeads:Map<number,any>,interfaceAnims:Map<number,number>};
const array=(a:ArrayLike<number>|null|undefined)=>a?Array.from(a):[];
const options=(a:(string|null)[]|null|undefined)=>(a??[]).map(x=>x==='hidden'?'':x??'');
const integer=(x:unknown,min=0,max=65535)=>{if(typeof x!=='number'||!Number.isInteger(x)||x<min||x>max)throw Error('Invalid integer');return x;};
const u16=(x:number)=>[x>>8,x&255];
const assets=path.resolve('../../Unity/Assets/LostCity274');
const sessions=new Map<string,Session>();
function queue(s:Session,opcode:number,payload:number[]=[],variable=false) {
    if(s.socket.state<0||s.socket.in.pos>8192)throw Error('Session closed or command queue full');
    s.socket.buffer(Buffer.from([opcode,...(variable?[payload.length]:[]),...payload]));
}
function createSession(username:string,startLumbridge=true) {
    if(!/^unity[a-z0-9_]{0,7}$/.test(username))throw Error('Use a local test name beginning with unity, max 12 characters');
    if(sessions.size>=10)throw Error('Native session limit reached');
    if(World.getPlayerByUsername(username))throw Error('Character is already logged in');
    const fixture=readTestFixture(username);
    const save=`data/players/main/${username}.sav`, socket=new UnitySocket();
    const player=PlayerLoading.load(username,new Packet(fs.existsSync(save)?fs.readFileSync(save):new Uint8Array()),socket) as NetworkPlayer;
    player.members=true; player.staffModLevel=0; player.lowMemory=false;
    const s:Session={token:randomUUID(),player,socket,touched:Date.now(),text:new Map(),hidden:new Map(),messages:[],activeTab:3,tutorialFlash:-1,countDialog:false,playerOps:[],audio:[],music:null,colours:new Map(),interfaceObjects:new Map(),knownNpcs:new Map(),interfaceHeads:new Map(),interfaceAnims:new Map()};
    const write=player.writeInner.bind(player);
    player.writeInner=(message:any)=>{
        const name=message.constructor.name;
        const audio=audioMessage(message);if(audio){const event={...audio,tick:World.currentTick};if(audio.kind==='music')s.music=event;else s.audio=[...s.audio.filter(e=>World.currentTick-e.tick<12),event].slice(-50);}
        if(name==='IfSetNpcHead')s.interfaceHeads.set(message.component,{kind:'npc',id:message.npc});
        if(name==='IfSetPlayerHead')s.interfaceHeads.set(message.component,{kind:'player'});
        if(name==='IfSetModel')s.interfaceHeads.delete(message.component);
        if(name==='IfSetAnim')s.interfaceAnims.set(message.component,message.seq);
        if(name==='IfSetObject')s.interfaceHeads.delete(message.component);
        if(name==='IfSetObject')s.interfaceObjects.set(message.component,{obj:message.obj,scale:message.scale});
        if(name==='IfSetColour')s.colours.set(message.component,message.colour);
        if(name==='IfSetText')s.text.set(message.component,message.text);
        if(name==='IfSetHide')s.hidden.set(message.component,!!message.hidden);
        if(name==='SetPlayerOp')s.playerOps[message.op-1]=message.value;
        if(name==='TutorialFlashSide')s.tutorialFlash=message.tab;
        if(name==='IfSetTabActive')s.activeTab=message.tab;
        if(name==='PCountDialog')s.countDialog=true;
        if(name==='IfClose')s.countDialog=false;
        if(name==='MessageGame'){s.messages.push(message.msg);s.messages=s.messages.slice(-30);}
        write(message);
    };
    const login=player.onLogin.bind(player);
    player.onLogin=()=>{
        // Set the selected entry state before the original login trigger can open
        // character design and enqueue tutorial_designed_character (which resets tutorial to 1).
        if(startLumbridge){const tutorial=VarPlayerType.getId('tutorial');if(tutorial>=0&&Number(player.getVar(tutorial))<1000)player.setVar(tutorial,1000);player.teleport(3222,3218,0);}
        login();if(!startLumbridge)return;
        player.closeModal();
        if(!fs.existsSync(save)){
            const complete=ScriptProvider.getByName('[label,tutorial_complete]');
            if(!complete)throw Error('Missing original tutorial completion script');
            player.executeScript(ScriptRunner.init(complete,player),true,true);
        }else{
            const tutorial=VarPlayerType.getId('tutorial');if(tutorial>=0&&Number(player.getVar(tutorial))<1000)player.setVar(tutorial,1000);
            player.modalTutorial=-1;
            const tabs=ScriptProvider.getByName('[proc,initalltabs]');if(tabs)player.executeScript(ScriptRunner.init(tabs,player),true,true);
        }
        player.allowDesign=false;player.teleport(3222,3218,0);player.messageGame('Welcome to Lumbridge.');applyTestFixture(player,fixture);
    };
    socket.state=1; World.newPlayers.add(player); sessions.set(s.token,s);
    return {token:s.token,revision:274,username};
}
function command(s:Session,c:any) {
    const op=()=>integer(c.op,1,5)-1;
    const approach=()=>{
        let x=integer(c.x),z=integer(c.z);
        if(c.kind==='loc'||c.target==='loc'){
            const loc=World.getLoc(x,z,s.player.level,integer(c.id));if(!loc)throw Error('Scenery no longer exists');
            const t=LocType.get(loc.type);const route=findPathToLoc(s.player.level,s.player.x,s.player.z,x,z,1,loc.width,loc.length,loc.angle,loc.shape,t.forceapproach);
            if(route.length){const dest=CoordGrid.unpackCoord(route[route.length-1]);x=dest.x;z=dest.z;}else{x=s.player.x;z=s.player.z;}
        }
        queue(s,138,[c.run?1:0,...u16(x),...u16(z)],true);
    };
    switch(c.kind) {
        case 'tab':s.activeTab=integer(c.id,0,13);if(s.tutorialFlash===s.activeTab){s.tutorialFlash=-1;queue(s,94,[s.activeTab]);}break;
        case 'count':{const n=integer(c.id,0,2147483647);queue(s,102,[n>>>24,(n>>>16)&255,(n>>>8)&255,n&255]);s.countDialog=false;break;}
        case 'invbutton':queue(s,[74,82,239,179,46][op()],[...u16(integer(c.id)),...u16(integer(c.slot)),...u16(integer(c.component))]);break;
        case 'reorder':queue(s,93,[...u16(integer(c.component)),...u16(integer(c.slot)),...u16(integer(c.targetSlot)),0]);break;
        case 'obj':approach();queue(s,[247,169,108,62,117][op()],[...u16(integer(c.x)),...u16(integer(c.z)),...u16(integer(c.id))]);break;
        case 'player':queue(s,[109,166,196,98,174][op()],u16(integer(c.id)));break;
        case 'use':case 'cast':{
            const target=String(c.target);
            if(target==='loc'||target==='obj')approach();
            const codes=c.kind==='use'?{inventory:136,npc:150,loc:60,obj:39,player:36}:{inventory:135,npc:181,loc:213,obj:91,player:240};
            if(!(target in codes))throw Error('Invalid action target');
            const payload=target==='inventory'?[...u16(integer(c.id)),...u16(integer(c.slot)),...u16(integer(c.component))]:target==='loc'||target==='obj'?[...u16(integer(c.x)),...u16(integer(c.z)),...u16(integer(c.id))]:u16(integer(c.id));
            payload.push(...(c.kind==='use'?[...u16(integer(c.useId)),...u16(integer(c.useSlot)),...u16(integer(c.useComponent))]:u16(integer(c.spell))));
            queue(s,codes[target as keyof typeof codes],payload);break;
        }
        case 'move': queue(s,207,[c.run?1:0,...u16(integer(c.x)),...u16(integer(c.z))],true);break;
        case 'npc': queue(s,[236,233,223,147,189][op()],u16(integer(c.id)));break;
        case 'loc': approach();queue(s,[215,103,187,157,127][op()],[...u16(integer(c.x)),...u16(integer(c.z)),...u16(integer(c.id))]);break;
        case 'button':queue(s,9,u16(integer(c.id)));break;
        case 'resume':queue(s,72,u16(integer(c.id)));break;
        case 'close':queue(s,51);break;
        case 'inventory':queue(s,[185,2,123,216,42][op()],[...u16(integer(c.id)),...u16(integer(c.slot,0,255)),...u16(integer(c.component))]);break;
        case 'appearance':
            {const body=c.body??s.player.body,colors=c.colors??s.player.colors;
            if(!Array.isArray(body)||body.length!==7||!Array.isArray(colors)||colors.length!==5)throw Error('Invalid design');
            queue(s,125,[integer(c.gender??s.player.gender,0,1),...body.map((x:number)=>integer(x,-1,255)&255),...colors.map((x:number)=>integer(x,0,255))]);}
            queue(s,9,u16(integer(c.id))); break;
        default:throw Error('Unsupported command');
    }
}
function appearance(p:Player,head=false){
    const parts:any[]=[];
    const worn=p.getInventory(p.appearanceInv);const skipped=new Set<number>();
    for(const item of worn?.items??[])if(item){const t=ObjType.get(item.id);skipped.add(t.wearpos2);skipped.add(t.wearpos3);}
    for(let slot=0;slot<12;slot++){
        if(skipped.has(slot))continue;
        const item=worn?.get(slot);
        if(item){const t=ObjType.get(item.id);parts.push({slot,models:(head?(p.gender===0?[t.manhead,t.manhead2]:[t.womanhead,t.womanhead2]):(p.gender===0?[t.manwear,t.manwear2,t.manwear3]:[t.womanwear,t.womanwear2,t.womanwear3])).filter(x=>x>=0),recolS:array(t.recol_s),recolD:array(t.recol_d),offsetY:head?0:(p.gender===0?t.manwearOffset:t.womanwearOffset)/128});}
        else{const id=p.getAppearanceInSlot(slot)-256;if(id>=0){const kit=IdkType.get(id);if(kit)parts.push({slot,models:array(head?kit.heads:kit.models).filter(x=>x>=0&&x<65535),recolS:array(kit.recol_s),recolD:array(kit.recol_d)});}}
    }
    const bodyS:number[]=[],bodyD:number[]=[];
    for(let i=0;i<5;i++){bodyS.push(Player.DESIGN_BODY_COLORS[i][0]);bodyD.push(Player.DESIGN_BODY_COLORS[i][p.colors[i]]);}
    for(const part of parts){part.recolS.push(...bodyS);part.recolD.push(...bodyD);}
    return parts;
}
function state(s:Session) {
    const p=s.player;
    if(p.slot<0)return {revision:274,pending:true,tick:World.currentTick};
    queue(s,120);
    const parts=appearance(p);
    const npcs:any[]=[],locs:any[]=[],backgroundLocs:any[]=[],objects:any[]=[],players:any[]=[];
    const ox=(p.x>>3)<<3,oz=(p.z>>3)<<3;
    for(let x=ox-48;x<=ox+48;x+=8)for(let z=oz-48;z<=oz+48;z+=8){
        for(let floor=0;floor<p.level;floor++)for(const loc of World.gameMap.getZone(x,z,floor).getAllLocsSafe()){
            const render=scenery(loc.type,loc.x,loc.z,floor,loc.shape,loc.angle);if(render)backgroundLocs.push({...render,key:floor+':'+render.key});
        }
        const zone=World.gameMap.getZone(x,z,p.level);
        for(const other of zone.getAllPlayersSafe())if(other.slot!==p.slot&&rsbuf.hasPlayer(p.slot,other.slot))players.push({id:other.slot,gender:other.gender,name:other.displayName,x:other.x,z:other.z,y:groundHeight(other.x,other.z,p.level),ready:other.readyanim,walk:other.walkanim,run:other.runanim,deathAnim:deathSequence(other),...animation(other),...facing(other),...combat(other),...actorEffects(other),parts:appearance(other),ops:s.playerOps,hp:other.levels[3],maxHp:other.baseLevels[3]});
        for(const n of zone.getAllNpcsSafe()){
            if(!rsbuf.hasNpc(p.slot,n.nid))continue;
            const t=NpcType.get(n.type);
            npcs.push({id:n.nid,type:n.type,hp:n.levels[3],maxHp:n.baseLevels[3],ready:t.readyanim,walk:t.walkanim,deathAnim:deathSequence(n),...animation(n),...facing(n),...combat(n),...actorEffects(n),x:n.x,z:n.z,y:groundHeight(n.x,n.z,p.level),name:t.name??'NPC',description:t.desc??'',combatLevel:t.vislevel,models:array(t.models),recolS:array(t.recol_s),recolD:array(t.recol_d),ops:options(t.op),size:t.size,scaleX:t.resizeh/128,scaleY:t.resizev/128});
        }
        for(const o of zone.getAllObjsSafe()){
            if(!o.isValid(p.hash64))continue;
            const t=ObjType.get(o.type);objects.push({id:o.type,key:`${o.x}:${o.z}:${o.type}`,x:o.x,z:o.z,y:groundHeight(o.x+.5,o.z+.5,p.level),name:t.name??'Item',description:t.desc??'',models:[t.model],recolS:array(t.recol_s),recolD:array(t.recol_d),ops:options(t.op),count:o.count});
        }
        for(const l of zone.getAllLocsSafe()){
            const render=scenery(l.type,l.x,l.z,p.level,l.shape,l.angle);if(render)locs.push(render);
        }
    }

    const ui:any[]=[];const visited=new Set<number>();
    function visit(id:number){if(id<0||visited.has(id))return;visited.add(id);const c=Component.get(id);if(!c||s.hidden.get(id)===true||(c.hide&&!s.hidden.has(id)))return;
        const text=interfaceText(p,c,s.text.get(id)??c.text??'');
        if(text||c.buttonType>0)ui.push({id,root:c.rootLayer,text,option:c.option??'',button:c.buttonType,active:interfaceActive(p,c),clientCode:c.clientCode,target:c.actionTarget,action:c.action??'',verb:c.actionVerb??''});
        for(const child of c.childId??[])visit(child);
    }
    for(const root of [p.modalMain,p.modalChat,p.modalSide,p.modalTutorial,...p.tabs])visit(root);
    // Recover labels from original component geometry for native controls.
    for(const layerId of visited){
        const layer=Component.get(layerId);
        if(!layer||!layer.childId)continue;
        for(let i=0;i<layer.childId.length;i++){
            const button=Component.get(layer.childId[i]);const widget=ui.find(w=>w.id===button?.id);
            if(!button||!widget||(widget.option&&widget.option!=="Select")||widget.text)continue;
            if(button.buttonType!==1&&button.buttonType!==3&&button.buttonType!==4&&!(button.buttonType===5&&(layer.comName??'').startsWith('combat_')))continue;
            const bx=layer.childX?.[i]??0,by=layer.childY?.[i]??0,labels:string[]=[];
            for(let j=0;j<layer.childId.length;j++){
                const label=Component.get(layer.childId[j]),x=layer.childX?.[j]??0,y=layer.childY?.[j]??0;
                if((button.buttonType===1||button.buttonType===3)&&label?.comType===4&&x>=bx&&x<bx+button.width&&y>=by&&y<by+button.height&&visited.has(label.id)){
                    const text=interfaceText(p,label,s.text.get(label.id)??label.text??'');if(text)labels.push(text);
                }
                if(button.buttonType===4&&label&&label.overLayer>=0&&x>=bx&&x<bx+button.width&&y>=by&&y<by+button.height){
                    const overlay=Component.get(label.overLayer);for(const textId of overlay?.childId??[]){const textComponent=Component.get(textId);if(textComponent?.comType===4&&textComponent.text){labels.push(interfaceText(p,textComponent,s.text.get(textId)??textComponent.text).replace(/\n/g,' · '));break;}}
                }
                if(button.buttonType===5&&label?.comType===4&&x>=bx+button.width-2&&x<bx+button.width+100&&y>=by-1&&y<by+button.height&&visited.has(label.id)){
                    const text=interfaceText(p,label,s.text.get(label.id)??label.text??'');if(text)labels.push(text);
                }
            }
            if(labels.length)widget.option=labels.join(' ');
        }
    }
    const inventory:any[]=[];
    for(const listener of p.invListeners){
        const c=Component.get(listener.com);if(!c||!p.isComponentVisible(c))continue;
        const inv=p.getInventoryFromListener(listener);
        if(!inv)continue;
        inv.items.forEach((item,slot)=>{if(item){const t=ObjType.get(item.id);inventory.push({title:c.comName==='trademain:inv'?'Your offer':c.comName==='trademain:otherinv'?"Other player's offer":'',id:item.id,count:item.count,graphic:itemGraphic(item.id,item.count),slot,component:listener.com,root:c.rootLayer,name:t.name??'Item',ops:c.operable?options(t.iop):[],buttons:options(c.iop),usable:c.usable});}});
    }
    // Death and removal can land between HTTP polls. Retain the final server
    // animation for NPCs this session actually saw; never synthesize a death
    // merely because an NPC left the player's view.
    for(const n of npcs)s.knownNpcs.set(n.id,{actor:n,tick:World.currentTick});
    const npcDeaths:any[]=[];
    for(const event of recentNpcDeaths()){
        const known=s.knownNpcs.get(event.id);if(!known||known.actor.type!==event.type||event.level!==p.level||World.currentTick-known.tick>=12)continue;
        const live=npcs.find(n=>n.id===event.id);
        if(live){if(live.hp<=0)Object.assign(live,event);continue;}
        npcDeaths.push({...known.actor,...event,hp:0});
    }
    for(const [id,known] of s.knownNpcs)if(World.currentTick-known.tick>=12)s.knownNpcs.delete(id);
    return {npcDeaths,dialogueHead:dialogueHead(p,s,()=>appearance(p,true)),musicSetting:Number(p.getVar(VarPlayerType.getId('option_music'))),soundSetting:Number(p.getVar(VarPlayerType.getId('option_sounds'))),running:p.run===1,sidebar:originalSidebar(p,s),overlay:originalOverlay(p,s,c=>interfaceText(p,c,s.text.get(c.id)??c.text??'')),revision:274,pending:false,effects:nearbyEffects(p),music:s.music,audio:s.audio.filter(e=>World.currentTick-e.tick<12),busy:p.delayed,tick:World.currentTick,regionX:ox,regionZ:oz,level:p.level,player:{id:p.slot,gender:p.gender,hp:p.levels[3],maxHp:p.baseLevels[3],ready:p.readyanim,walk:p.walkanim,run:p.runanim,deathAnim:deathSequence(p),...animation(p),...facing(p),...combat(p),...actorEffects(p),x:p.x,z:p.z,y:groundHeight(p.x,p.z,p.level),name:p.displayName,parts},npcs,locs,backgroundLocs,objects,players,ui,inventory,tabs:p.tabs,chatRoot:p.modalChat,mainRoot:p.modalMain,tutorialRoot:p.modalTutorial,sideRoot:p.modalSide,activeTab:s.activeTab,countDialog:s.countDialog,energy:p.runenergy,tutorialProgress:Number(p.getVar(VarPlayerType.getId('tutorial'))),combatStyle:Number(p.getVar(VarPlayerType.getId('com_mode'))),baseLevels:array(p.baseLevels),gender:p.gender,body:p.body,colors:p.colors,messages:s.messages,levels:array(p.levels),experience:array(p.stats),design:p.allowDesign?Array.from({length:IdkType.count},(_,id)=>({id,type:IdkType.get(id).type,disabled:IdkType.get(id).disable})).filter(x=>!x.disabled):[],colorCounts:Player.DESIGN_BODY_COLORS.map(x=>x.length),allowDesign:p.allowDesign};
}
export function startUnityGateway() {
    installEvents();installEffects();
    const server=http.createServer(async(req,res)=>{
        res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
        const json=(status:number,value:unknown)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(value));};
        try{
            if(req.headers.origin){json(403,{error:'Native clients only'});return;}
            const url=new URL(req.url??'/', 'http://127.0.0.1');
            if(req.method==='GET'&&url.pathname==='/health'){json(200,{revision:274,tick:World.currentTick,status:'ok'});return;}
            const asset=/^\/v1\/(models|textures)\/(\d{1,5})$/.exec(url.pathname);
            if(req.method==='GET'&&asset){const file=path.join(assets,asset[1],asset[2]+(asset[1]==='models'?'.ob2':'.png'));if(!fs.existsSync(file)){json(404,{error:'Asset unavailable'});return;}res.writeHead(200,{'Content-Type':asset[1]==='models'?'application/octet-stream':'image/png'});res.end(fs.readFileSync(file));return;}
            let body:any={};
            if(req.method==='POST'){const chunks:Buffer[]=[];let length=0;for await(const chunk of req){length+=chunk.length;if(length>2048)throw Error('Request too large');chunks.push(chunk);}body=JSON.parse(Buffer.concat(chunks).toString()||'{}');}
            if(req.method==='POST'&&url.pathname==='/v1/session'){json(200,createSession(String(body.username??''),body.startLumbridge!==false));return;}
            const key=(req.headers.authorization??'').replace(/^Bearer /,'');const s=sessions.get(key);
            if(!s){json(401,{code:'SESSION_EXPIRED',error:'Session required'});return;}
            if(s.socket.state<0){sessions.delete(key);json(401,{code:'SESSION_EXPIRED',error:'Session ended'});return;}
            s.touched=Date.now();
            const overlayMatch=/^\/v1\/overlay\/([a-f0-9]{64})$/.exec(url.pathname);
            if(req.method==='GET'&&overlayMatch){const overlay=originalOverlay(s.player,s,c=>interfaceText(s.player,c,s.text.get(c.id)??c.text??''));const node=overlay?.nodes.find((n:any)=>n.image===overlayMatch[1]);if(!node){json(404,{error:'Interface no longer open'});return;}const bytes=await overlayPng(node);res.writeHead(200,{'Content-Type':'image/png','Content-Length':bytes.length});res.end(bytes);return;}
            const audioMatch=/^\/v1\/audio\/(sound|music)\/(\d{1,5})$/.exec(url.pathname);
            if(req.method==='GET'&&audioMatch){const file=await audioFile(audioMatch[1],Number(audioMatch[2]),integer(Number(url.searchParams.get('loops')??1),1,8));if(!sessions.has(key)){json(401,{code:'SESSION_EXPIRED',error:'Session ended'});return;}res.writeHead(200,{'Content-Type':'audio/wav','Content-Length':fs.statSync(file).size});fs.createReadStream(file).pipe(res);return;}
            const seqMatch=/^\/v1\/sequence\/(\d{1,5})$/.exec(url.pathname);
            if(req.method==='GET'&&seqMatch){json(200,sequence(Number(seqMatch[1])));return;}
            if(req.method==='GET'&&url.pathname==='/v1/chunk'){
                const x=integer(Number(url.searchParams.get('x'))),z=integer(Number(url.searchParams.get('z'))),level=integer(Number(url.searchParams.get('level')),0,3);
                if(Math.abs(x-s.player.x)>112||Math.abs(z-s.player.z)>112||x%16||z%16)throw Error('Chunk outside view');
                const result=terrain(x,z,level,16);json(200,{...result,locs:staticScenery(x,z,level,16)});return;
            }
            if(req.method==='GET'&&url.pathname==='/v1/terrain'){const x=(s.player.x>>3)<<3,z=(s.player.z>>3)<<3;json(200,terrain(x,z,s.player.level));return;}
            if(req.method==='GET'&&url.pathname==='/v1/state'){json(200,state(s));return;}
            if(req.method==='POST'&&url.pathname==='/v1/action'){command(s,body);json(202,{queued:true,tick:World.currentTick});return;}
            if(req.method==='DELETE'&&url.pathname==='/v1/session'){s.socket.close();sessions.delete(s.token);json(200,{closed:true});return;}
            json(404,{error:'Unknown endpoint'});
        }catch(e){json(400,{error:e instanceof Error?e.message:'Request failed'});}
    });
    setInterval(()=>{for(const [key,s] of sessions)if(Date.now()-s.touched>60000){s.socket.close();sessions.delete(key);}},5000).unref();
    server.listen(8890,'127.0.0.1',()=>console.log('UNITY_GATEWAY_READY revision=274 port=8890'));
}
