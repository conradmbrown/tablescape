using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    [Serializable] class SkillSuite {public SkillCase[] cases;}
    [Serializable] class SkillCase {public string name,username;public SkillStep[] steps;}
    [Serializable] class SkillStep {
        public string label,kind,target,name,operation,message,choices;public int item,useItem,button,skill=-1,product,delta,x,z,level=-1;
        public float timeout=30,retrySeconds;public int healthGain;public bool requireAnimation,requireHeld,expectOverlay,expectDialog,expectMain,expectCount,expectNoXp,expectChatClosed,activeValue,requireLowerFloor;public int count=1,equippedId,targetId,checkButton,minX,maxX,minZ,maxZ,inventoryComponent,expectedItemCount=-1,mainRoot=-1,style=-1;
    }
    [Serializable] class SkillResult {public string test,step,status,detail;public int animationFrames,poseChanges,heldModels;public string renderedSequences;public int skill,xpBefore,xpAfter,itemBefore,itemAfter,hpBefore,hpAfter,tick;}
    [Serializable] class SkillReport {public string mode="Native Unity actions through normal gameplay handlers; fixture setup excluded from results";public List<SkillResult> results=new List<SkillResult>();}
    SkillReport skillReport=new SkillReport();string skillOutput;
    int ItemCount(int id,int component=0){var items=state.inventory??Array.Empty<Item>();bool banking=Array.Exists(items,i=>Array.Exists(i.buttons??Array.Empty<string>(),b=>b.Contains("Deposit")));int n=0;foreach(var i in items)if((component>0?i.component==component:banking?Array.Exists(i.buttons??Array.Empty<string>(),b=>b.Contains("Deposit")):i.component==3214)&&i.id==id)n+=i.count;return n;}

    Actor SkillTarget(SkillStep s){var list=s.target=="npc"?state.npcs:s.target=="obj"?state.objects:s.target=="player"?state.players:state.locs;Actor best=null;float d=float.MaxValue;foreach(var a in list??Array.Empty<Actor>()){
        if(s.targetId>0&&a.id!=s.targetId)continue;
        if(!string.IsNullOrEmpty(s.name)&&!string.Equals(a.name,s.name,StringComparison.OrdinalIgnoreCase))continue;
        if(!string.IsNullOrEmpty(s.operation)&&Array.IndexOf(a.ops??Array.Empty<string>(),s.operation)<0)continue;
        float next=Mathf.Abs(a.x-state.player.x)+Mathf.Abs(a.z-state.player.z);if(next<d){d=next;best=a;}
    }return best;}
    void FocusTestWidget(Widget widget){int tab=Array.IndexOf(state.tabs,widget.root);if(tab>=0&&tab!=activeTab){activeTab=tab;Send(new Action{kind="tab",id=tab});}}
    bool SkillAct(SkillStep s,out string error){error="";selectedItem=null;selectedSpell=null;
        var item=FindItem(s.item);
        switch(s.kind){
            case "held":if(item==null){error="Inventory item absent: "+s.item;return false;}Held(item,s.count);break;
            case "use":if(item==null||FindItem(s.useItem)==null){error="Use item missing";return false;}selectedItem=FindItem(s.useItem);TargetAction(new Action{kind="inventory",id=item.id,slot=item.slot,component=item.component});break;
            case "target":case "useTarget":case "cast":var actor=SkillTarget(s);if(actor==null){error="Target absent: "+s.name+" / "+s.operation;return false;}
                if(s.kind=="useTarget"){if(item==null){error="Use item missing: "+s.item;return false;}selectedItem=item;}
                if(s.kind=="cast"){var spell=Array.Find(state.ui,w=>w.id==s.button);if(spell==null){error="Spell widget missing";return false;}FocusTestWidget(spell);WidgetButton(spell);}
                Target(s.target,actor,string.IsNullOrEmpty(s.operation)?1:Array.IndexOf(actor.ops,s.operation)+1);break;
            case "button":var w=Array.Find(state.ui,a=>a.id==s.button);if(w==null||w.button<=0){error="Interactive widget absent: "+s.button;return false;}FocusTestWidget(w);WidgetButton(w);break;
            case "invbutton":var inv=Array.Find(state.inventory,i=>i.id==s.item&&Array.Exists(i.buttons??Array.Empty<string>(),b=>b==s.operation));if(inv==null){error="Inventory operation absent: "+s.operation;return false;}Send(new Action{kind="invbutton",id=inv.id,slot=inv.slot,component=inv.component,op=Array.IndexOf(inv.buttons,s.operation)+1});break;
            case "count":Send(new Action{kind="count",id=s.count});break;
            case "close":if(inputFile!=null&&HasOriginalOverlay)RequestInput("close-original-overlay","left",overlayCloseScreen);else Send(new Action{kind="close"});break;
            case "move":Send(new Action{kind="move",x=s.x,z=s.z});break;
            case "tab":activeTab=s.button;Send(new Action{kind="tab",id=s.button});break;
            case "dialogue":case "wait":break;
            default:error="Unknown step "+s.kind;return false;
        }return true;
    }
    bool SkillOutcome(SkillStep s,int xp,int count,int hp){
        if(s.expectOverlay&&(!OverlayAssetsReady()||originalOverlayDraws<2))return false;
        if(s.kind=="close"&&state.mainRoot>=0)return false;
        if(s.requireLowerFloor){bool ground=false;foreach(var chunk in chunks.Values)if(chunk.level==0&&Math.Abs(chunk.x-chunkX)<=16&&Math.Abs(chunk.z-chunkZ)<=16&&chunk.meshes.Count>0&&!chunk.interactive)ground=true;if(!ground||state.backgroundLocs==null||state.backgroundLocs.Length==0)return false;}
        if(s.healthGain>0&&(state.player.hp<hp+s.healthGain||state.player.hp>state.player.maxHp))return false;
        if(s.maxX>0&&(state.player.x<s.minX||state.player.x>s.maxX||state.player.z<s.minZ||state.player.z>s.maxZ))return false;
        if(s.expectChatClosed&&state.chatRoot>=0)return false;
        if(s.checkButton>0&&!Array.Exists(state.ui,w=>w.id==s.checkButton&&w.active==s.activeValue))return false;
        if(s.equippedId>0&&!Array.Exists(state.inventory,i=>i.component==1688&&i.id==s.equippedId))return false;
        if(s.style>=0&&state.combatStyle!=s.style)return false;
        if(s.skill>=0&&(s.expectNoXp?state.experience[s.skill]!=xp:state.experience[s.skill]<=xp))return false;
        if(s.product>0&&(s.expectedItemCount>=0?ItemCount(s.product,s.inventoryComponent)!=s.expectedItemCount:s.delta>=0?ItemCount(s.product,s.inventoryComponent)<count+s.delta:ItemCount(s.product,s.inventoryComponent)>count+s.delta))return false;
        if(s.mainRoot>=0&&state.mainRoot!=s.mainRoot)return false;
        if(s.expectDialog&&state.chatRoot<0)return false;if(s.expectMain&&state.mainRoot<0)return false;if(s.expectCount&&!state.countDialog)return false;
        if(s.level>=0&&state.level!=s.level)return false;
        if(s.kind=="move"&&(state.player.x!=s.x||state.player.z!=s.z))return false;
        if(!string.IsNullOrEmpty(s.message)&&!Array.Exists(state.messages,m=>m.IndexOf(s.message,StringComparison.OrdinalIgnoreCase)>=0)&&!Array.Exists(state.ui,w=>(w.text??"").IndexOf(s.message,StringComparison.OrdinalIgnoreCase)>=0))return false;
        return true;
    }
    IEnumerator SkillsPlaytest(){
        string manifest=null;foreach(var arg in Environment.GetCommandLineArgs()){if(arg.StartsWith("--scape-input-file="))inputFile=arg.Substring(19);if(arg.StartsWith("--scape-suite="))manifest=arg.Substring(14);if(arg.StartsWith("--scape-results="))skillOutput=arg.Substring(16);}
        if(manifest==null||skillOutput==null){Debug.LogError("SCAPE_SKILLS missing manifest/results path");Application.Quit(1);yield break;}
        Directory.CreateDirectory(skillOutput);var suite=JsonUtility.FromJson<SkillSuite>(File.ReadAllText(manifest));bool failed=false;
        foreach(var test in suite.cases){
            Debug.Log("SCAPE_SKILL_BEGIN "+test.name);smokeFailed=false;actions.Clear();username=test.username;var joinRoutine=StartCoroutine(Join());
            yield return AwaitState(()=>state!=null,45,test.name+"_login");
            if(state!=null){yield return AwaitState(()=>chunks.Count>=9,60,test.name+"_rendered");yield return new WaitForSeconds(2);
                if(state.tutorialProgress!=1000){failed=true;skillReport.results.Add(new SkillResult{test=test.name,step="Tutorial completion retained",status="FAIL",detail="tutorial="+state.tutorialProgress});}
                File.WriteAllText(Path.Combine(skillOutput,test.name+"-before.json"),JsonUtility.ToJson(state,true));
                int stepNumber=0;foreach(var step in test.steps){
                    stepNumber++;
                    // Original scripts deliberately ignore world clicks during p_delay.
                    // Wait for the action lock to end, as a player would after an animation.
                    float readyDeadline=Time.realtimeSinceStartup+15;while(state.busy&&Time.realtimeSinceStartup<readyDeadline)yield return new WaitForSeconds(.2f);
                    var observation=new SkillAnimationObservation();var observe=StartCoroutine(ObserveSkillAnimation(observation,Path.Combine(skillOutput,test.name+"-step"+stepNumber+"-animation"),step.skill==16));
                    int xp=step.skill>=0?state.experience[step.skill]:0, count=ItemCount(step.product,step.inventoryComponent), hp=state.player.hp;bool sent=SkillAct(step,out string error);
                    string previousDialogue="";float nextDialogue=0;
                    float end=Time.realtimeSinceStartup+step.timeout,nextRetry=Time.realtimeSinceStartup+step.retrySeconds;
                    yield return new WaitForSeconds(step.expectNoXp?Mathf.Min(5,step.timeout):2);
                    while(sent&&!SkillOutcome(step,xp,count,hp)&&Time.realtimeSinceStartup<end){
                        if(step.kind=="dialogue"&&state.chatRoot>=0&&Time.realtimeSinceStartup>=nextDialogue){
                            var widgets=Array.FindAll(state.ui,w=>w.root==state.chatRoot);string fingerprint=string.Join("|",Array.ConvertAll(widgets,w=>w.id+":"+w.text));
                            if(fingerprint!=previousDialogue){Widget choice=null;foreach(var text in (step.choices??"").Split('|'))if(text.Length>0){choice=Array.Find(widgets,w=>w.button>0&&Plain(w.text??"").Contains(text));if(choice!=null)break;}
                                if(choice==null)choice=Array.Find(widgets,w=>w.button==6);if(choice!=null){WidgetButton(choice);previousDialogue=fingerprint;nextDialogue=Time.realtimeSinceStartup+1;}
                            }
                        }
                        if(step.retrySeconds>0&&Time.realtimeSinceStartup>=nextRetry){SkillAct(step,out error);nextRetry=Time.realtimeSinceStartup+step.retrySeconds;}yield return new WaitForSeconds(.3f);}
                    // XP can arrive on the first animation frame. Keep observing
                    // long enough to verify the visible action, not just its result.
                    float visualDeadline=Time.realtimeSinceStartup+2;
                    while(Time.realtimeSinceStartup<visualDeadline&&((step.requireAnimation&&(observation.frames.Count<2||observation.poseChanges<=1))||(step.requireHeld&&observation.heldModels==0)))yield return null;
                    observation.running=false;StopCoroutine(observe);
                    bool visualPass=(!step.requireAnimation||observation.frames.Count>=2&&observation.poseChanges>1)&&(!step.requireHeld||observation.heldModels>0);
                    bool pass=sent&&SkillOutcome(step,xp,count,hp)&&visualPass;bool checkedOutcome=step.expectOverlay||step.kind=="close"||step.mainRoot>=0||step.healthGain>0||step.skill>=0||step.product>0||step.equippedId>0||step.style>=0||step.checkButton>0||step.expectDialog||step.expectMain||step.expectCount||step.expectChatClosed||step.level>=0||step.maxX>0||step.kind=="move"||!string.IsNullOrEmpty(step.message);var result=new SkillResult{animationFrames=observation.frames.Count,poseChanges=observation.poseChanges,heldModels=observation.heldModels,renderedSequences=string.Join(",",observation.sequences),test=test.name,step=step.label,status=pass?(checkedOutcome?"PASS":"ACTION"):"FAIL",detail=(!visualPass?"Animation/held-model assertion failed. ":"")+(sent?string.Join(" | ",state.messages)+" | Dialogue: "+string.Join(" / ",Array.ConvertAll(Array.FindAll(state.ui,w=>w.root==state.chatRoot),w=>Plain(w.text??""))):error),skill=step.skill,xpBefore=xp,xpAfter=step.skill>=0?state.experience[step.skill]:0,itemBefore=count,itemAfter=ItemCount(step.product,step.inventoryComponent),hpBefore=hp,hpAfter=state.player.hp,tick=state.tick};skillReport.results.Add(result);
                    File.WriteAllText(Path.Combine(skillOutput,"results.json"),JsonUtility.ToJson(skillReport,true));Debug.Log("SCAPE_SKILL_RESULT "+JsonUtility.ToJson(result));
                    captureBase=Path.Combine(skillOutput,test.name+"-step"+stepNumber);yield return CapturePlay("");if(step.expectOverlay)File.WriteAllText(captureBase+".json",JsonUtility.ToJson(state,true));
                    if(!pass){failed=true;break;}
                }
                yield return new WaitForSeconds(1);captureBase=Path.Combine(skillOutput,test.name);yield return CapturePlay("");File.WriteAllText(captureBase+"-after.json",JsonUtility.ToJson(state,true));
            }else{failed=true;skillReport.results.Add(new SkillResult{test=test.name,step="login",status="FAIL",detail=status});}
            // End the old polling coroutine before the next test can acquire a new token.
            if(state!=null&&Array.Exists(test.steps,s=>s.operation=="Attack")){
                // Cancel combat through ordinary movement and escape before logout. Otherwise
                // a pending normal logout keeps the NPC busy for the following test.
                Send(new Action{kind="move",x=(int)state.player.x+12,z=(int)state.player.z,run=true});yield return new WaitForSeconds(14);
            }
            failed|=smokeFailed;StopCoroutine(joinRoutine);actions.Clear();yield return Logout();yield return new WaitForSeconds(2);lastServerTab=-1;
        }
        File.WriteAllText(Path.Combine(skillOutput,"results.json"),JsonUtility.ToJson(skillReport,true));Debug.Log("SCAPE_SKILLS_COMPLETE failures="+failed+" assertions="+skillReport.results.Count);Application.Quit(failed?1:0);
    }
}
}
