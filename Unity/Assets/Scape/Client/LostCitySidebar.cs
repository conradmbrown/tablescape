using System;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    [Serializable] public class Sidebar {public int root;public SideNode node;}
    [Serializable] public class SideNode {public int id,type,x,y,width,height,scroll,over=-1,button,font,colour,overColour,clientCode,marginX,marginY,alpha;public bool active,center,shadow,fill,hidden;public string text,graphic,option;public SideNode[] children;public int[] slotX,slotY;public string[] slotGraphics;}
    [Serializable] class ModelIconOffset {public string key;public int x,y;}
    [Serializable] class ModelIconOffsets {public ModelIconOffset[] offsets;}
    Dictionary<string,Vector2> modelIconOffsets;
    readonly Dictionary<string,Texture2D> menuIcons=new Dictionary<string,Texture2D>();readonly Dictionary<int,Vector2> menuScroll=new Dictionary<int,Vector2>();
    readonly Dictionary<string,Rect> itemHitRects=new Dictionary<string,Rect>();
    readonly Dictionary<int,Rect> menuHitRects=new Dictionary<int,Rect>();Vector2 sideGroupOrigin;bool drawingSidebar;
    int sideHover=-1,sideDraws,iconsDrawn,missingMenuIcons;string sideTooltip;Rect hoveredSideRect;
    static readonly int[] TabIcon={0,1,2,3,4,5,6,-1,7,8,9,10,11,12};
    float SideScale=>Mathf.Min(1.4f,(Screen.height-105)/343f);
    Rect SideRect=>new Rect(Screen.width-360,Screen.height-343*SideScale,249*SideScale,343*SideScale);
    Rect SideScreen(Rect local)=>new Rect(SideRect.x+local.x*SideScale,SideRect.y+local.y*SideScale,local.width*SideScale,local.height*SideScale);
    Texture2D MenuIcon(string key){if(string.IsNullOrEmpty(key))return null;if(!menuIcons.TryGetValue(key,out var t)){t=Resources.Load<Texture2D>("Icons/"+key);menuIcons[key]=t;if(!t){missingMenuIcons++;Debug.LogWarning("SCAPE_MENU_ICON_MISSING "+key);}}return t;}
    void DrawMenuIcon(string key,float x,float y,bool flipX=false,bool flipY=false){var t=MenuIcon(key);if(!t)return;if(key.StartsWith("model-")){if(modelIconOffsets==null){modelIconOffsets=new Dictionary<string,Vector2>();var asset=Resources.Load<TextAsset>("Icons/model-offsets");if(asset)foreach(var o in JsonUtility.FromJson<ModelIconOffsets>(asset.text).offsets)modelIconOffsets[o.key]=new Vector2(o.x,o.y);}if(modelIconOffsets.TryGetValue(key,out var offset)){x+=offset.x;y+=offset.y;}}GUI.DrawTextureWithTexCoords(new Rect(x,y,t.width,t.height),t,new Rect(flipX?1:0,flipY?1:0,flipX?-1:1,flipY?-1:1),true);iconsDrawn++;}
    void MenuText(string text,int x,int y,int width,int colour=0xff981f,int font=1,bool center=false,bool shadow=true){DrawBitmapText(new OverlayNode{text=text,x=x,y=y,width=width,font=font,colour=colour,shadow=shadow,center=center},false);GUI.color=Color.white;}
    Rect TabRect(int index){int c=index%7;int[] xs={22,54,82,110,153,181,209};return new Rect(xs[c],index<7?8:306,index%7==3?43:28,32);}
    void DrawIconTabs(){
        DrawMenuIcon("backhmid1-0",0,0);DrawMenuIcon("backbase2-0",-20,306);
        int selected=Mathf.Clamp(activeTab,0,13),col=selected%7;var selectedRect=TabRect(selected);string stone=col==0||col==6?"redstone1-0":col==3?"redstone3-0":"redstone2-0";if(state.sideRoot<0)DrawMenuIcon(stone,selectedRect.x,selectedRect.y,col>3,selected>=7);
        int[] topX={29,53,82,115,153,180,208},topY={13,11,11,12,13,11,13};int[] bottomX={0,54,82,117,154,181,206};
        for(int i=0;i<14;i++){if(TabIcon[i]<0||state.tabs==null||i>=state.tabs.Length||state.tabs[i]<0)continue;var hit=TabRect(i);DrawMenuIcon("sideicons-"+TabIcon[i],i<7?topX[i]:bottomX[i-7],i<7?topY[i]:308);if(hit.Contains(Event.current.mousePosition)){sideTooltip=TabNames[i];hoveredSideRect=SideScreen(hit);}if(GUI.Button(hit,GUIContent.none,GUIStyle.none)){activeTab=i;Send(new Action{kind="tab",id=i});selectedComponent=-1;}}
    }
    int FindSideHover(SideNode n,Vector2 mouse){if(n==null||n.hidden)return -1;mouse-=new Vector2(n.x,n.y);int found=-1;if(n.over>=0&&new Rect(0,0,n.width,n.height).Contains(mouse))found=n.over;if(n.children!=null){if(!new Rect(0,0,n.width,n.height).Contains(mouse))return found;var delta=menuScroll.TryGetValue(n.id,out var sc)?sc:Vector2.zero;foreach(var child in n.children){int next=FindSideHover(child,mouse+delta);if(next>=0)found=next;}}return found;}
    void DrawSideNode(SideNode n,Vector2 origin){
        if(n==null||n.hidden&&n.id!=sideHover)return;Vector2 at=origin+new Vector2(n.x,n.y);var rect=new Rect(at.x,at.y,n.width,n.height);
        if(n.type==0){
            var oldGroup=sideGroupOrigin;sideGroupOrigin+=rect.position;GUI.BeginGroup(rect);var offset=menuScroll.TryGetValue(n.id,out var saved)?saved:Vector2.zero;bool scrolling=n.scroll>n.height;
            if(scrolling){sideGroupOrigin-=offset;}
            if(scrolling)offset=GUI.BeginScrollView(new Rect(0,0,n.width,n.height),offset,new Rect(0,0,n.width-16,n.scroll),false,true,GUIStyle.none,GUIStyle.none);
            foreach(var child in n.children??Array.Empty<SideNode>())DrawSideNode(child,Vector2.zero);
            if(scrolling){GUI.EndScrollView();offset.y=DrawOriginalScrollbar(n,offset.y);menuScroll[n.id]=offset;}GUI.EndGroup();sideGroupOrigin=oldGroup;return;
        }
        bool hovered=rect.Contains(Event.current.mousePosition);
        if(n.type==6)DrawMenuIcon(n.graphic,at.x+n.width/2-256,at.y+n.height/2-167);
        else if(n.type==5)DrawMenuIcon(n.graphic,at.x,at.y);
        else if(n.type==3){var color=OverlayColour(n.colour);color.a=(256-n.alpha)/256f;if(n.fill)FillRect(rect,color);else{FillRect(new Rect(rect.x,rect.y,rect.width,1),color);FillRect(new Rect(rect.x,rect.yMax-1,rect.width,1),color);FillRect(new Rect(rect.x,rect.y,1,rect.height),color);FillRect(new Rect(rect.xMax-1,rect.y,1,rect.height),color);}}
        else if(n.type==4)DrawBitmapText(new OverlayNode{text=n.text,x=(int)at.x,y=(int)at.y,width=n.width,font=n.font,center=n.center,shadow=n.shadow,colour=n.colour,overColour=n.overColour},hovered);
        else if(n.type==2)DrawIconInventory(n,at);
        GUI.color=Color.white;
        if(n.button>0){if(Event.current.type==EventType.Repaint){menuHitRects[n.id]=SideScreen(new Rect(sideGroupOrigin+rect.position,rect.size));}var w=Array.Find(state.ui,w=>w.id==n.id);if(hovered&&n.over<0&&sideHover<0&&w!=null){sideTooltip=Plain(!string.IsNullOrEmpty(w.option)&&w.option!="Select"?w.option:!string.IsNullOrEmpty(w.action)?w.action:w.text);hoveredSideRect=menuHitRects.TryGetValue(n.id,out var r)?r:SideRect;}
            if(selectedSpell?.id==n.id){FillRect(new Rect(rect.x,rect.y,rect.width,1),Color.white);FillRect(new Rect(rect.x,rect.yMax-1,rect.width,1),Color.white);}
            if(hovered&&w!=null&&InterfaceRightClick()){OpenWidgetMenu(w,ScreenMouse);Event.current.Use();}
            if(GUI.Button(rect,GUIContent.none,GUIStyle.none)&&w!=null)WidgetButton(w);
        }
    }
    float DrawOriginalScrollbar(SideNode node,float value){float x=node.width-16,track=node.height-32,thumb=Mathf.Max(8,track*node.height/node.scroll),travel=track-thumb;FillRect(new Rect(x,16,16,track),OverlayColour(0x23201b));DrawMenuIcon("scrollbar-0",x,0);DrawMenuIcon("scrollbar-1",x,node.height-16);if(GUI.Button(new Rect(x,0,16,16),GUIContent.none,GUIStyle.none))value-=20;if(GUI.Button(new Rect(x,node.height-16,16,16),GUIContent.none,GUIStyle.none))value+=20;value=GUI.VerticalScrollbar(new Rect(x,16,16,track),value,node.height,0,node.scroll,GUIStyle.none);float y=16+travel*Mathf.Clamp01(value/(node.scroll-node.height));FillRect(new Rect(x,y,16,thumb),OverlayColour(0x4d4233));FillRect(new Rect(x,y,1,thumb),OverlayColour(0x766654));FillRect(new Rect(x,y,16,1),OverlayColour(0x766654));FillRect(new Rect(x+15,y,1,thumb),OverlayColour(0x332b23));return Mathf.Clamp(value,0,node.scroll-node.height);}
    void DrawIconInventory(SideNode node,Vector2 at){
        for(int slot=0;slot<node.width*node.height;slot++){float x=at.x+(slot%node.width)*(32+node.marginX)+(slot<(node.slotX?.Length??0)?node.slotX[slot]:0),y=at.y+(slot/node.width)*(32+node.marginY)+(slot<(node.slotY?.Length??0)?node.slotY[slot]:0);var rect=new Rect(x,y,32,32);var item=Array.Find(state.inventory??Array.Empty<Item>(),i=>i.component==node.id&&i.slot==slot);
            if(item==null){if(slot<(node.slotGraphics?.Length??0))DrawMenuIcon(node.slotGraphics[slot],x,y);continue;}
            if(Event.current.type==EventType.Repaint){var screen=GUIUtility.GUIToScreenPoint(rect.position);itemHitRects[item.component+":"+item.slot]=drawingSidebar?SideScreen(new Rect(sideGroupOrigin+rect.position,rect.size)):new Rect(screen.x,screen.y,32,32);}
            DrawMenuIcon(item.graphic,x,y);if(item.count>1)MenuText(item.count>=10000000?(item.count/1000000)+"M":item.count>=100000?(item.count/1000)+"K":item.count.ToString(),(int)x,(int)y,32,item.count>=10000000?0x00ff80:item.count>=100000?0xffffff:0xffff00,0);
            if(selectedItem!=null&&selectedItem.component==item.component&&selectedItem.slot==item.slot){FillRect(new Rect(x,y,32,1),Color.white);FillRect(new Rect(x,y+31,32,1),Color.white);}
            bool hit=rect.Contains(Event.current.mousePosition);if(hit){sideTooltip=item.name;var point=GUIUtility.GUIToScreenPoint(rect.position);hoveredSideRect=new Rect(point.x,point.y,32*SideScale,32*SideScale);}
            if(hit&&InterfaceRightClick()){OpenInventoryMenu(item,ScreenMouse);Event.current.Use();}
            if(GUI.Button(rect,GUIContent.none,GUIStyle.none)){if(selectedItem!=null||selectedSpell!=null)TargetAction(new Action{kind="inventory",id=item.id,slot=item.slot,component=item.component});else{int op=Array.FindIndex(item.ops??Array.Empty<string>(),v=>!string.IsNullOrEmpty(v));int button=Array.FindIndex(item.buttons??Array.Empty<string>(),v=>!string.IsNullOrEmpty(v));if(op>=0&&op<4)Held(item,op+1);else if(button>=0)Send(new Action{kind="invbutton",id=item.id,slot=item.slot,component=item.component,op=button+1});else if(item.usable)selectedItem=item;else if(op>=0)Held(item,op+1);}}
        }
    }
    void OpenInventoryMenu(Item item,Vector2 origin){menu.Clear();if(selectedItem!=null||selectedSpell!=null)menu.Add(new MenuEntry{label=(selectedItem!=null?"Use "+selectedItem.name:"Cast "+Plain(selectedSpell.action))+" -> "+item.name,invoke=()=>TargetAction(new Action{kind="inventory",id=item.id,slot=item.slot,component=item.component})});else{
        for(int i=0;i<Math.Min(4,item.ops?.Length??0);i++){int op=i+1;if(!string.IsNullOrEmpty(item.ops[i]))menu.Add(new MenuEntry{label=item.ops[i]+" "+item.name,invoke=()=>Held(item,op)});}if(item.usable)menu.Add(new MenuEntry{label="Use "+item.name,invoke=()=>{selectedItem=item;selectedSpell=null;}});if((item.ops?.Length??0)>4&&!string.IsNullOrEmpty(item.ops[4]))menu.Add(new MenuEntry{label=item.ops[4]+" "+item.name,invoke=()=>Held(item,5)});for(int i=0;i<(item.buttons?.Length??0);i++){int op=i+1;if(!string.IsNullOrEmpty(item.buttons[i]))menu.Add(new MenuEntry{label=item.buttons[i]+" "+item.name,invoke=()=>Send(new Action{kind="invbutton",id=item.id,slot=item.slot,component=item.component,op=op})});}}
        menu.Add(new MenuEntry{label="Examine "+item.name,invoke=()=>SetNotice(item.name)});ShowContextMenu(origin);
    }
    bool DrawNativeSidebar(){
        if(state==null||overlayFonts==null||state.allowDesign)return false;if(state.activeTab!=lastServerTab){activeTab=state.activeTab;lastServerTab=state.activeTab;}
        sideTooltip=null;var old=GUI.matrix;GUI.matrix=Matrix4x4.TRS(new Vector3(SideRect.x,SideRect.y,0),Quaternion.identity,new Vector3(SideScale,SideScale,1));GUI.color=Color.white;
        FillRect(new Rect(22,44,227,262),new Color32(74,62,47,255));DrawMenuIcon("backvmid2-0",0,45);DrawMenuIcon("backvmid3-0",-20,197);var joint=MenuIcon("backhmid2-0");if(joint)GUI.DrawTextureWithTexCoords(new Rect(0,178,37,19),joint,new Rect(516f/joint.width,0,37f/joint.width,1),true);DrawMenuIcon("invback-0",37,45);DrawMenuIcon("backright2-0",227,45);DrawIconTabs();
        if(state.sidebar?.node!=null&&state.sidebar.root==(state.sideRoot>=0?state.sideRoot:state.tabs[activeTab])){drawingSidebar=true;sideGroupOrigin=new Vector2(37,45);GUI.BeginGroup(new Rect(37,45,190,261));sideHover=FindSideHover(state.sidebar.node,Event.current.mousePosition);DrawSideNode(state.sidebar.node,Vector2.zero);GUI.EndGroup();drawingSidebar=false;}
        GUI.matrix=old;GUI.color=Color.white;
        if(!string.IsNullOrEmpty(sideTooltip)&&!menuOpen){var matrix=GUI.matrix;GUI.matrix=Matrix4x4.TRS(new Vector3(18,62,0),Quaternion.identity,new Vector3(1.4f,1.4f,1));MenuText(sideTooltip,0,0,500,0xffffff,1);GUI.matrix=matrix;}
        if(selectedItem!=null||selectedSpell!=null){GUILayout.BeginArea(new Rect(Screen.width-350,SideRect.y-54,330,48));GUILayout.Label(selectedItem!=null?"Use "+selectedItem.name+" on…":"Cast "+Plain(selectedSpell.action)+" on…");if(GUILayout.Button("Cancel selection")){selectedItem=null;selectedSpell=null;}GUILayout.EndArea();}
        if(state.countDialog){GUILayout.BeginArea(new Rect(Screen.width-350,SideRect.y-90,330,80),GUI.skin.box);GUILayout.Label("Enter amount");countInput=GUILayout.TextField(countInput,10);if(GUILayout.Button("Confirm")&&int.TryParse(countInput,out int count)&&count>=0)Send(new Action{kind="count",id=count});GUILayout.EndArea();}
        if(Event.current.type==EventType.Repaint)sideDraws++;return true;
    }
}
}
