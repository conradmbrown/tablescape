using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Scape.Assets;
namespace Scape.Client {
public sealed partial class LostCityClient {
    Item selectedItem;Widget selectedSpell;bool runEnabled;string countInput="1",notice="";int activeTab=3;int lastServerTab=-1;int designGender=-1;int[] designBody,designColors;
    static readonly string[] TabNames={"Combat","Skills","Quests","Inventory","Equipment","Prayer","Magic","Unused","Friends","Ignore","Logout","Settings","Controls","Music"};
    static readonly string[] SkillNames={"Attack","Defence","Strength","Hitpoints","Ranged","Prayer","Magic","Cooking","Woodcutting","Fletching","Fishing","Firemaking","Crafting","Smithing","Mining","Herblore","Agility","Thieving","","","Runecraft"};
    void Recolour(GameObject child,Part part,int id){
        if(part.recolS==null||part.recolD==null||part.recolS.Length==0)return;
        var filter=child.GetComponent<MeshFilter>();var mesh=Instantiate(filter.sharedMesh);var colors=mesh.colors;
        var owner=child.AddComponent<LostCityOwnedMesh>();owner.mesh=mesh;
        var renderer=child.GetComponent<MeshRenderer>();var materials=renderer.sharedMaterials;
        var texturedVertices=new bool[mesh.vertexCount];
        // Original recolour changes the face value, which is a texture ID on textured
        // faces. Doors use the same slab as walls, with texture 2 changed to wood 0/4.
        for(int sub=0;sub<materials.Length;sub++){
            var material=materials[sub];
            if(!material.name.StartsWith("cache-texture-")||!int.TryParse(material.name.Substring(14),out int sourceTexture)||sourceTexture<0)continue;
            foreach(int vertex in mesh.GetTriangles(sub))texturedVertices[vertex]=true;
            int texture=sourceTexture;
            for(int k=0;k<Math.Min(part.recolS.Length,part.recolD.Length);k++)if(texture==part.recolS[k])texture=part.recolD[k];
            if(texture==sourceTexture)continue;
            if(texture<0||texture>=catalogue.textures.Length||!catalogue.textures[texture]){Debug.LogError($"Original recolour texture unavailable: model {id}, {sourceTexture}->{texture}");continue;}
            var instance=new Material(material){name="cache-texture-"+texture,mainTexture=catalogue.textures[texture]};
            materials[sub]=instance;owner.materials.Add(instance);
        }
        renderer.sharedMaterials=materials;
        for(int k=0;k<Math.Min(part.recolS.Length,part.recolD.Length);k++){
            if(part.recolS[k]==part.recolD[k])continue;
            Color from=LostCityModel.PaletteColour(part.recolS[k]),to=LostCityModel.PaletteColour(part.recolD[k]);
            for(int i=0;i<colors.Length;i++)if(!texturedVertices[i]&&Mathf.Abs(colors[i].r-from.r)<.0001f&&Mathf.Abs(colors[i].g-from.g)<.0001f&&Mathf.Abs(colors[i].b-from.b)<.0001f){to.a=colors[i].a;colors[i]=to;}
        }
        mesh.colors=colors;filter.sharedMesh=mesh;
    }
    void Target(string kind,Actor actor,int op){
        TargetAction(new Action{kind=kind,id=actor.id,x=(int)actor.x,z=(int)actor.z,op=op});
    }
    void TargetAction(Action action){
        if(selectedItem!=null){action.target=action.kind;action.kind="use";action.useId=selectedItem.id;action.useSlot=selectedItem.slot;action.useComponent=selectedItem.component;}
        else if(selectedSpell!=null){action.target=action.kind;action.kind="cast";action.spell=selectedSpell.id;}
        Send(action);selectedItem=null;selectedSpell=null;
    }

    bool Visible(int root){return state.tabs==null||Array.IndexOf(state.tabs,root)<0||(state.sideRoot<0&&state.tabs[Mathf.Clamp(activeTab,0,state.tabs.Length-1)]==root);}
    void WidgetButton(Widget w){
        if(w.clientCode==326){Send(new Action{kind="appearance",id=w.id,gender=designGender<0?state.gender:designGender,body=designBody??state.body,colors=designColors??state.colors});return;}
        if(w.clientCode==205){StartCoroutine(Logout());return;}
        if(w.button==2){selectedSpell=w;selectedItem=null;return;}
        if(w.button==3){Send(new Action{kind="close"});return;}
        Send(new Action{kind=w.clientCode==326?"appearance":w.button==6?"resume":"button",id=w.id});
    }
    int selectedComponent=-1,selectedSlot=-1;
    void DrawInventory(int rootOnly=-1){
        var groups=new Dictionary<int,List<Item>>();
        foreach(var item in state.inventory??Array.Empty<Item>())if((rootOnly<0||item.root==rootOnly)&&Visible(item.root)){if(!groups.TryGetValue(item.component,out var group)){group=new List<Item>();groups[item.component]=group;}group.Add(item);}
        foreach(var pair in groups){
            var items=pair.Value;var buttons=items[0].buttons??Array.Empty<string>();string title=string.IsNullOrEmpty(items[0].title)?"Inventory":items[0].title;
            if(string.IsNullOrEmpty(items[0].title)){if(Array.Exists(buttons,b=>b.Contains("Withdraw")))title="Bank";else if(Array.Exists(buttons,b=>b.Contains("Buy")))title="Shop stock";else if(Array.Exists(buttons,b=>b.Contains("Remove")))title="Equipment";}
            GUILayout.Space(8);GUILayout.Label(title);
            if(overlayFonts!=null){int maxSlot=0;foreach(var item in items)maxSlot=Math.Max(maxSlot,item.slot);int columns=rootOnly>=0?8:4;var area=GUILayoutUtility.GetRect(columns*40,((maxSlot/columns)+1)*40);DrawIconInventory(new SideNode{id=pair.Key,width=columns,height=maxSlot/columns+1,marginX=8,marginY=8},area.position);continue;}
            for(int i=0;i<items.Count;i+=2){GUILayout.BeginHorizontal();for(int j=i;j<Math.Min(i+2,items.Count);j++){
                var item=items[j];if(GUILayout.Button(item.name+(item.count>1?" ×"+item.count:""),GUILayout.Width(151),GUILayout.MinHeight(36))){
                    if(selectedItem!=null||selectedSpell!=null)TargetAction(new Action{kind="inventory",id=item.id,slot=item.slot,component=item.component});
                    else{selectedComponent=item.component;selectedSlot=item.slot;}
                }
            }GUILayout.EndHorizontal();}
            var selected=items.Find(i=>i.component==selectedComponent&&i.slot==selectedSlot);
            if(selected!=null){
                GUILayout.Label(selected.name);
                if(selected.usable&&GUILayout.Button("Use")){selectedItem=selected;selectedSpell=null;}
                for(int op=0;op<(selected.ops?.Length??0);op++)if(!string.IsNullOrEmpty(selected.ops[op])&&GUILayout.Button(selected.ops[op]))Send(new Action{kind="inventory",id=selected.id,slot=selected.slot,component=selected.component,op=op+1});
                for(int op=0;op<(selected.buttons?.Length??0);op++)if(!string.IsNullOrEmpty(selected.buttons[op])&&GUILayout.Button(selected.buttons[op]))Send(new Action{kind="invbutton",id=selected.id,slot=selected.slot,component=selected.component,op=op+1});
            }
        }
    }
    void ActorActions(string kind,Actor a){
        if(selectedItem!=null||selectedSpell!=null){if(GUILayout.Button("Target "+a.name))Target(kind,a,1);return;}
        for(int i=0;i<(a.ops?.Length??0);i++)if(!string.IsNullOrEmpty(a.ops[i])&&GUILayout.Button(a.ops[i]+" "+a.name))Target(kind,a,i+1);
    }
    void OnGUI(){
        ApplyClassicSkin();HandleContextMenuInput();DrawMinimap();
        if(token==null||connectionPaused||joining||disconnecting){
            GUILayout.BeginArea(new Rect(250,90,500,230),GUI.skin.box);
            GUILayout.Label(status);
            if(connectionLoopActive||disconnecting){if(!disconnecting&&GUILayout.Button("Cancel reconnect"))StartCoroutine(Logout());}
            else {GUILayout.Label("Local test character (starts with unity)");GUI.enabled=token==null;username=GUILayout.TextField(username,12);GUI.enabled=true;if(GUILayout.Button(everConnected?"Reconnect":"Connect to Lost City"))StartCoroutine(Join());if(token!=null&&GUILayout.Button("Log out"))StartCoroutine(Logout());}
            GUILayout.EndArea();return;
        }
        DrawChatPanel();DrawMainModal();
        if(DrawNativeSidebar()){DrawFeedback();return;}
        DrawFeedback();
        GUILayout.BeginArea(new Rect(Screen.width-360,10,350,Screen.height-20),GUI.skin.box);scroll=GUILayout.BeginScrollView(scroll);
        if(state!=null){
            if(state.activeTab!=lastServerTab){activeTab=state.activeTab;lastServerTab=state.activeTab;}
            GUILayout.Label(state.player.name+" · "+state.player.x+", "+state.player.z);
            GUILayout.Label("Hitpoints "+state.player.hp+" / "+state.player.maxHp);
            runEnabled=GUILayout.Toggle(runEnabled,"Run · energy "+state.energy/100+"%");
            for(int row=0;row<5;row++){GUILayout.BeginHorizontal();for(int col=0;col<3;col++){int t=row*3+col;if(t>=14)break;GUI.enabled=state.tabs!=null&&t<state.tabs.Length&&state.tabs[t]>=0;
                if(GUILayout.Button((activeTab==t?"• ":"")+TabNames[t])){activeTab=t;Send(new Action{kind="tab",id=t});}
            }GUI.enabled=true;GUILayout.EndHorizontal();}
            
            if(selectedItem!=null||selectedSpell!=null){GUILayout.Label(selectedItem!=null?"Use "+selectedItem.name+" on…":"Cast "+Plain(selectedSpell.action)+" on…");if(GUILayout.Button("Cancel selection")){selectedItem=null;selectedSpell=null;}}
            if(state.countDialog){GUILayout.Label("Enter amount");countInput=GUILayout.TextField(countInput,10);if(GUILayout.Button("Confirm amount")&&int.TryParse(countInput,out int amount)&&amount>=0)Send(new Action{kind="count",id=amount});}
            if(activeTab==1&&state.levels!=null)for(int i=0;i<Math.Min(SkillNames.Length,state.levels.Length);i++)if(!string.IsNullOrEmpty(SkillNames[i]))GUILayout.Label(SkillNames[i]+": "+state.levels[i]+" / "+state.baseLevels[i]+" · XP "+state.experience[i]/10);
            if(state.allowDesign&&state.design!=null){
                if(designGender<0){designGender=state.gender;designBody=(int[])state.body.Clone();designColors=(int[])state.colors.Clone();}
                GUILayout.Label("Character design");
                if(GUILayout.Button(designGender==0?"Body: male":"Body: female")){designGender=1-designGender;for(int part=0;part<7;part++){var kit=Array.Find(state.design,k=>k.type==part+designGender*7);designBody[part]=kit==null?-1:kit.id;}}
                string[] names={"Hair","Jaw","Torso","Arms","Hands","Legs","Feet"};
                for(int part=0;part<7;part++)if(GUILayout.Button(names[part]+": style "+designBody[part])){int type=part+designGender*7;var kits=Array.FindAll(state.design,k=>k.type==type);int index=Array.FindIndex(kits,k=>k.id==designBody[part]);if(kits.Length>0)designBody[part]=kits[(index+1)%kits.Length].id;}
                for(int color=0;color<5;color++)if(GUILayout.Button("Colour "+(color+1)+": "+designColors[color]))designColors[color]=(designColors[color]+1)%state.colorCounts[color];
            }
            foreach(var w in state.ui??Array.Empty<Widget>()){
                if(w.root==state.chatRoot||w.root==state.mainRoot||!Visible(w.root)||w.clientCode>=300&&w.clientCode<=325)continue;
                if(w.button>0){string label=Plain(string.IsNullOrEmpty(w.option)?w.text:w.option);if(string.IsNullOrWhiteSpace(label)||label=="Select")label=Plain(w.action);if(string.IsNullOrWhiteSpace(label))label="Option";
                    if(GUILayout.Button((w.active&&(w.button==4||w.button==5)?"• ":"")+label))WidgetButton(w);
                }else if(!string.IsNullOrEmpty(w.text))GUILayout.Label(Plain(w.text));
            }
            if(activeTab==11||activeTab==13)DrawAudioSettings();
            DrawInventory();
            if(GUILayout.Button("Log out"))StartCoroutine(Logout());
        }
        GUILayout.EndScrollView();GUILayout.EndArea();
    }
}
public sealed class LostCityOwnedMesh:MonoBehaviour {public Mesh mesh;public System.Collections.Generic.List<Material> materials=new System.Collections.Generic.List<Material>();void OnDestroy(){if(mesh)Destroy(mesh);foreach(var material in materials)if(material)Destroy(material);}}
}
