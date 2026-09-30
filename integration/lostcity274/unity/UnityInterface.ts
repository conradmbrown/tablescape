import Component from '#/cache/config/Component.js';
import VarBitType from '#/cache/config/VarBitType.js';
import Player,{getExpByLevel} from '#/engine/entity/Player.js';
import World from '#/engine/World.js';
// Evaluate the original interface's read-only expression bytecode against game state.
export function value(p:Player,c:Component,index:number):number{
    const code=c.scripts?.[index];if(!code)return 0;
    let pc=0,acc=0,arithmetic=0;
    while(pc<code.length){const op=code[pc++];let v=0,next=0;if(op===0)return acc;
        if(op===1)v=p.levels[code[pc++]];
        else if(op===2)v=p.baseLevels[code[pc++]];
        else if(op===3)v=Math.floor(p.stats[code[pc++]]/10);
        else if(op===4||op===10){const com=code[pc++],obj=code[pc++];const listener=p.invListeners.find(l=>l.com===com);if(listener){const inv=p.getInventoryFromListener(listener);for(const item of inv?.items??[])if(item?.id===obj)v+=item.count;}if(op===10&&v)v=999999999;}
        else if(op===5)v=p.vars[code[pc++]];
        else if(op===6)v=Math.floor(getExpByLevel(p.baseLevels[code[pc++]]+1)/10);
        else if(op===7)v=Math.floor(p.vars[code[pc++]]*100/46875);
        else if(op===8)v=p.getCombatLevel();
        else if(op===9)v=Array.from(p.baseLevels).reduce((a,b,i)=>a+(i===18||i===19?0:b),0);
        else if(op===11)v=Math.floor(p.runenergy/100);
        else if(op===12)v=Math.floor(p.runweight/1000);
        else if(op===13){const n=p.vars[code[pc++]];v=(n&(1<<code[pc++]))?1:0;}
        else if(op===14){const b=VarBitType.get(code[pc++]);v=(p.vars[b.basevar]>>>b.startbit)&((1<<(b.endbit-b.startbit+1))-1);}
        else if(op>=15&&op<=17)next=op-14;
        else if(op===18)v=p.x;else if(op===19)v=p.z;else if(op===20)v=code[pc++];else return 0;
        if(next)arithmetic=next;else{if(arithmetic===0)acc+=v;else if(arithmetic===1)acc-=v;else if(arithmetic===2&&v)acc=Math.trunc(acc/v);else if(arithmetic===3)acc*=v;arithmetic=0;}
    }return acc;
}
export function interfaceText(p:Player,c:Component,text:string){return text.replace(/%([1-5])/g,(_,n)=>{const v=value(p,c,Number(n)-1);return v>=999999999?'*':String(v);}).replace(/\\n/g,'\n');}

export function interfaceActive(p:Player,c:Component):boolean {
    if(!c.scriptComparator?.length)return false;
    return Array.from(c.scriptComparator).every((op,i)=>{const actual=value(p,c,i),expected=c.scriptOperand?.[i]??0;return op===2?actual<expected:op===3?actual>expected:op===4?actual!==expected:actual===expected;});
}
