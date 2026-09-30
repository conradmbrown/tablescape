using System;
using UnityEngine;
namespace Scape.Client {
public sealed partial class LostCityClient {
    bool contextInputTrace;
    int pressedMenuRow=-1;bool interfaceRightPressed;Vector2 interfaceRightOrigin;
    Vector2 ScreenMouse=>new Vector2(Input.mousePosition.x,Screen.height-Input.mousePosition.y);
    // Match world menus: open on release. Opening in IMGUI's mouse-down pass
    // races Update's dismissal of the previous menu during that same press.
    bool InterfaceRightClick(){
        var e=Event.current;if(e.button!=1)return false;
        if(contextInputTrace&&(e.type==EventType.MouseDown||e.type==EventType.MouseUp))Debug.Log("SCAPE_CONTEXT_INPUT "+e.type+" pointer="+ScreenMouse+" gui="+GUIUtility.GUIToScreenPoint(e.mousePosition)+" frame="+Time.frameCount);
        if(e.type==EventType.MouseDown){interfaceRightPressed=true;interfaceRightOrigin=GUIUtility.GUIToScreenPoint(e.mousePosition);e.Use();return false;}
        if(e.type!=EventType.MouseUp)return false;
        bool click=interfaceRightPressed&&Vector2.Distance(GUIUtility.GUIToScreenPoint(e.mousePosition),interfaceRightOrigin)<=5;
        interfaceRightPressed=false;return click;
    }
    void ShowContextMenu(Vector2 origin){
        menu.Add(new MenuEntry{label="Cancel",invoke=()=>{}});menuOrigin=origin;pressedMenuRow=-1;
        float h=30+menu.Count*24;
        menuRect=new Rect(Mathf.Clamp(origin.x,5,Screen.width-335),Mathf.Clamp(origin.y,5,Mathf.Max(5,Screen.height-h-5)),330,h);
        menuOpen=true;menusOpened++;
    }
    void OpenWidgetMenu(Widget widget,Vector2 origin){
        menu.Clear();string label;
        if(widget.button==2){
            string verb=Plain(widget.verb);int space=verb.IndexOf(' ');if(space>=0)verb=verb.Substring(0,space);
            label=(string.IsNullOrEmpty(verb)?"Cast":verb)+" "+Plain(widget.action);
        }else label=widget.button==3?"Close":Plain(!string.IsNullOrWhiteSpace(widget.option)?widget.option:!string.IsNullOrWhiteSpace(widget.text)?widget.text:widget.action);
        if(!string.IsNullOrWhiteSpace(label))menu.Add(new MenuEntry{label=label,invoke=()=>WidgetButton(widget)});
        ShowContextMenu(origin);
    }
    void HandleContextMenuInput(){
        if(!menuOpen)return;var e=Event.current;
        if(e.button!=0||(e.type!=EventType.MouseDown&&e.type!=EventType.MouseUp))return;
        bool inside=menuRect.Contains(e.mousePosition);
        int row=inside?Mathf.FloorToInt((e.mousePosition.y-menuRect.y-27)/24):-1;
        if(row<0||row>=menu.Count)row=-1;
        if(e.type==EventType.MouseDown){pressedMenuRow=row;if(inside)e.Use();return;}
        if(pressedMenuRow>=0||inside){
            // Consume before drawing the shop/sidebar controls underneath the
            // floating menu, so choosing Buy/Sell/Cast cannot click through.
            var invoke=row>=0&&row==pressedMenuRow?menu[row].invoke:null;
            pressedMenuRow=-1;e.Use();
            if(invoke!=null){menuOpen=false;invoke();}
        }
    }
}
}
