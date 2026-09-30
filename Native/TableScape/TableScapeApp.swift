import SwiftUI
import CompositorServices
import simd

@MainActor final class TableScapeModel:ObservableObject {
    let session:GameSession
    let placement:TablePlacement
    let scene:GameScene
    let popupCoordinator=GamePopupCoordinator()
    @Published var immersive=false
    @Published var volumeOpen=false
    private var volumeOwner:UUID?
    private var retiringVolume=false
    @Published var changingPresentation=false
    var volumeMenuTapCount=0
    var volumeAppearanceCount=0
    var volumeDisappearanceCount=0
    var volumeOpenRequests=0
    var tableLeaveRequests=0
    var homeAppearanceCount=0
    var didStart=false
    var immersiveRenderer:ImmersiveMetalRenderer?
    init(){let s=GameSession(),p=TablePlacement();session=s;placement=p;scene=GameScene(session:s,placement:p)}
    func volumeAppeared(_ owner:UUID) {volumeAppearanceCount += 1;volumeOwner=owner;volumeOpen=true}
    func volumeDisappeared(_ owner:UUID) {
        volumeDisappearanceCount += 1
        // A dismissed window can finish disappearing after its replacement opens.
        guard volumeOwner == owner else{return}
        volumeOwner=nil;volumeOpen=false
    }
    func showTableWindow(open:OpenWindowAction,dismiss:DismissWindowAction,dismissSpace:DismissImmersiveSpaceAction) async {
        volumeOpenRequests += 1
        guard !changingPresentation else{return};changingPresentation=true
        defer{changingPresentation=false}
        if immersive {await dismissSpace();placement.stop();immersive=false}
        dismiss(id:"placement")
        if !volumeOpen {volumeOwner=nil}
        retiringVolume=false;volumeOpen=true
        open(id:"table-window",value:"table")
        // The volume owns its anchored game menu. Retiring detached controls
        // avoids an existing taskbar remaining outside the user's current view.
        dismiss(id:"taskbar")
    }
    func leaveTable(open:OpenWindowAction,dismiss:DismissWindowAction,dismissSpace:DismissImmersiveSpaceAction) async {
        tableLeaveRequests += 1
        guard !changingPresentation else{return};changingPresentation=true
        defer{changingPresentation=false}
        if immersive {await dismissSpace();placement.stop();immersive=false}
        if volumeOpen {volumeOwner=nil;retiringVolume=true;volumeOpen=false}
        open(id:"main",value:"main")
        dismiss(id:"placement");dismiss(id:"taskbar")
    }
    func homeAppeared(dismiss:DismissWindowAction) {
        homeAppearanceCount += 1
        guard retiringVolume else{return}
        retiringVolume=false
        // The system keeps the last window alive until its replacement exists.
        dismiss(id:"table-window")
    }
}
private struct TableVolumeWindow:View {
    @ObservedObject var model:TableScapeModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var owner=UUID()
    var body:some View {
        VolumetricTableView(model:model)
            .modifier(GamePopupRouter(session:model.session,coordinator:model.popupCoordinator))
            .onAppear{
                model.volumeAppeared(owner)
                // Wait until this window exists before retiring the last 2D window.
                dismissWindow(id:"main")
                dismissWindow(id:"taskbar")
            }
            .onDisappear{model.volumeDisappeared(owner)}
    }
}
@main struct TableScapeApp:App {
    @StateObject private var model=TableScapeModel()
    var body:some Scene {
        WindowGroup(id:"main",for:String.self) {_ in TableScapeHome(model:model)} defaultValue:{"main"}.defaultSize(width:1280,height:940).restorationBehavior(.disabled)
        WindowGroup("TableScape controls",id:"taskbar",for:String.self) {_ in FloatingGameControls(model:model)} defaultValue:{"controls"}.defaultSize(width:640,height:60).windowResizability(.contentSize).restorationBehavior(.disabled).defaultWindowPlacement{_,context in if let window=context.windows.first(where:{$0.id=="main"}){return WindowPlacement(.trailing(window))};return WindowPlacement(.utilityPanel)}
        WindowGroup("Table",id:"table-window",for:String.self) {_ in
            TableVolumeWindow(model:model)
        } defaultValue:{"table"}
            .windowStyle(.volumetric)
            .defaultSize(width:1.3,height:0.9,depth:0.9,in:.meters)
            .windowResizability(.contentSize).restorationBehavior(.disabled)
        WindowGroup("Table placement",id:"placement",for:String.self) {_ in PlacementView(placement:model.placement).padding(22).frame(width:480)} defaultValue:{"placement"}.defaultSize(width:480,height:580).restorationBehavior(.disabled).defaultWindowPlacement{_,context in if let window=context.windows.first(where:{$0.id=="main"}){return WindowPlacement(.leading(window))};return WindowPlacement(.utilityPanel)}
        WindowGroup("Click options",id:GamePopup.options.rawValue,for:String.self) {_ in GamePopupWindow(popup:.options,session:model.session,scene:model.scene,coordinator:model.popupCoordinator)} defaultValue:{GamePopup.options.rawValue}
            .defaultSize(width:340,height:300).windowResizability(.contentSize).restorationBehavior(.disabled)
            .defaultWindowPlacement{_,context in if let controls=context.windows.first(where:{$0.id=="taskbar"}){return WindowPlacement(.leading(controls))};return WindowPlacement(.utilityPanel)}
        WindowGroup("Conversation",id:GamePopup.dialogue.rawValue,for:String.self) {_ in GamePopupWindow(popup:.dialogue,session:model.session,scene:model.scene,coordinator:model.popupCoordinator)} defaultValue:{GamePopup.dialogue.rawValue}
            .defaultSize(width:580,height:280).windowResizability(.contentSize).restorationBehavior(.disabled)
            .defaultWindowPlacement{_,context in if let controls=context.windows.first(where:{$0.id=="taskbar"}){return WindowPlacement(.leading(controls))};return WindowPlacement(.utilityPanel)}
        WindowGroup("Game interface",id:GamePopup.activity.rawValue,for:String.self) {_ in GamePopupWindow(popup:.activity,session:model.session,scene:model.scene,coordinator:model.popupCoordinator)} defaultValue:{GamePopup.activity.rawValue}
            .defaultSize(width:620,height:580).windowResizability(.contentSize).restorationBehavior(.disabled)
            .defaultWindowPlacement{_,context in if let controls=context.windows.first(where:{$0.id=="taskbar"}){return WindowPlacement(.leading(controls))};return WindowPlacement(.utilityPanel)}
        WindowGroup("Enter amount",id:GamePopup.amount.rawValue,for:String.self) {_ in GamePopupWindow(popup:.amount,session:model.session,scene:model.scene,coordinator:model.popupCoordinator)} defaultValue:{GamePopup.amount.rawValue}
            .defaultSize(width:340,height:190).windowResizability(.contentSize).restorationBehavior(.disabled)
            .defaultWindowPlacement{_,context in if let activity=context.windows.first(where:{$0.id==GamePopup.activity.rawValue}){return WindowPlacement(.above(activity))};return WindowPlacement(.utilityPanel)}
        WindowGroup("Map",id:GamePopup.map.rawValue,for:String.self) {_ in GamePopupWindow(popup:.map,session:model.session,scene:model.scene,coordinator:model.popupCoordinator)} defaultValue:{GamePopup.map.rawValue}
            .defaultSize(width:240,height:300).windowResizability(.contentSize).restorationBehavior(.disabled)
            .defaultWindowPlacement{_,context in if let controls=context.windows.first(where:{$0.id=="taskbar"}){return WindowPlacement(.above(controls))};return WindowPlacement(.utilityPanel)}
        WindowGroup("Nearby & messages",id:GamePopup.explore.rawValue,for:String.self) {_ in GamePopupWindow(popup:.explore,session:model.session,scene:model.scene,coordinator:model.popupCoordinator)} defaultValue:{GamePopup.explore.rawValue}
            .defaultSize(width:420,height:520).windowResizability(.contentSize).restorationBehavior(.disabled)
            .defaultWindowPlacement{_,context in if let controls=context.windows.first(where:{$0.id=="taskbar"}){return WindowPlacement(.leading(controls))};return WindowPlacement(.utilityPanel)}
        ImmersiveSpace(id:"table") {
            CompositorLayer(configuration:TableCompositorConfiguration()) {layer in
                layer.onSpatialEvent={events in
                    for event in events where event.phase == .ended || event.phase == .active {
                        guard let ray=event.selectionRay else{continue}
                        let o=SIMD3<Float>(Float(ray.origin.x),Float(ray.origin.y),Float(ray.origin.z))
                        let d=SIMD3<Float>(Float(ray.direction.x),Float(ray.direction.y),Float(ray.direction.z))
                        model.scene.pick(origin:o,direction:d,menu:true,highlightOnly:event.phase == .active)
                    }
                }
                Task {await model.placement.start()
                    do {let renderer=try ImmersiveMetalRenderer(layer:layer,exchange:model.scene.exchange,tracking:model.placement.trackingSource);model.immersiveRenderer=renderer;renderer.onInvalidated={ [weak model, weak renderer] in Task { @MainActor in
                        guard let model, let renderer, model.immersiveRenderer === renderer else { return }
                        model.placement.stop();model.immersive=false;model.immersiveRenderer=nil
                    }};renderer.start()}
                    catch {model.scene.status=error.localizedDescription}
                }
            }
        }.immersionStyle(selection:.constant(.mixed),in:.mixed).immersiveEnvironmentBehavior(.coexist)
    }
}
struct TableScapeHome:View {
    @ObservedObject var model:TableScapeModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPlacement=false
    var body:some View {
        VStack(spacing:16) {
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading,spacing:3) {Text("TableScape").font(.system(size:32,weight:.semibold,design:.serif));Text("A world at your table").font(.subheadline).foregroundStyle(.secondary)}
                Spacer()
                Button("Open table window",systemImage:"cube.transparent") {Task {
                    await model.showTableWindow(open:openWindow,dismiss:dismissWindow,dismissSpace:dismissImmersiveSpace)
                }}.buttonStyle(.borderedProminent).disabled(model.changingPresentation).accessibilityIdentifier("table.window.open")
                Button("Use real table",systemImage:"visionpro") {Task {
                    guard !model.immersive,!model.changingPresentation else{return}
                    model.changingPresentation=true
                    defer{model.changingPresentation=false}
                    if model.volumeOpen {dismissWindow(id:"table-window");model.volumeOpen=false}
                    let result=await openImmersiveSpace(id:"table")
                    if case .opened=result{model.immersive=true;showPlacement=false;openWindow(id:"taskbar",value:"controls");if !model.placement.snapshot.isConfirmed {openWindow(id:"placement",value:"placement")}}
                }}.disabled(model.immersive || model.changingPresentation).accessibilityIdentifier("table.immersive")
                Button("Floating taskbar",systemImage:"rectangle.3.group"){openWindow(id:"taskbar",value:"controls")}.accessibilityIdentifier("game.taskbar")
            }
            HStack(alignment:.top,spacing:18) {
                VStack(spacing:12) {
                    SceneBoard(scene:model.scene)
                    GameConnectionView(session:model.session,showSetup:false)
                }.frame(maxWidth:.infinity)
                GamePanels(session:model.session,assets:model.scene.assets,immersive:model.immersive,volumeOpen:model.volumeOpen,tableControlsContent:AnyView(TableViewControls(scene:model.scene)),onOpenTableWindow:{
                    Task {await model.showTableWindow(open:openWindow,dismiss:dismissWindow,dismissSpace:dismissImmersiveSpace)}
                },onLeaveTable:{
                    Task {await model.leaveTable(open:openWindow,dismiss:dismissWindow,dismissSpace:dismissImmersiveSpace)}
                }).frame(width:392)
            }
        }.padding(24).frame(minWidth:1050,minHeight:720)
        .task {guard !model.didStart else{return};model.didStart=true;model.scene.start()
            let args=ProcessInfo.processInfo.arguments
            #if targetEnvironment(simulator)
            if !args.contains("--tablescape-unplaced") {model.placement.placeVirtualTable(width:1.3,depth:0.9)}
            #endif
            if let user=args.first(where:{$0.hasPrefix("--tablescape-user=")}) {model.session.username=String(user.dropFirst(18))}
            if args.contains("--tablescape-test") {Task{await NativePlaytest.run(model:model)}}
            else if args.contains("--tablescape-connect") {model.session.connect()}
            if args.contains("--tablescape-profile"){Task{await NativeProfileCapture.run(model:model)}}
            if args.contains("--tablescape-volume") {await model.showTableWindow(open:openWindow,dismiss:dismissWindow,dismissSpace:dismissImmersiveSpace)}
            else if args.contains("--tablescape-immersive"){let result=await openImmersiveSpace(id:"table");if case .opened=result{model.immersive=true;openWindow(id:"taskbar",value:"controls")}}
        }
        .modifier(GamePopupRouter(session:model.session,coordinator:model.popupCoordinator))
        .onAppear{model.homeAppeared(dismiss:dismissWindow)}
        .onChange(of:scenePhase){_,phase in if phase == .active && model.immersive {Task{await model.placement.start()}}}
    }
}
struct SceneBoard:View {
    @ObservedObject var scene:GameScene
    var body:some View {
        VStack(spacing:8) {
            ZStack(alignment:.bottomLeading) {
                MetalBoardPreview(scene:scene).frame(minHeight:380,maxHeight:.infinity).clipShape(RoundedRectangle(cornerRadius:20))
                VStack(alignment:.leading,spacing:5){Text(scene.selectedName.isEmpty ? "Tap to walk · Hold for actions":scene.selectedName).font(.callout);Text(scene.status).font(.caption).foregroundStyle(.secondary)}.padding(14).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:12)).padding(12).allowsHitTesting(false)
            }
            HStack(spacing:24) {
                VStack(spacing:10) {
                    HStack {Image(systemName:"arrow.triangle.2.circlepath");Slider(value:$scene.orbit,in:-Double.pi...Double.pi).accessibilityLabel("Orbit board")}
                    HStack {Image(systemName:"angle");Slider(value:$scene.tilt,in:0.3...1.45).accessibilityLabel("Viewing angle")}
                    HStack {Image(systemName:"magnifyingglass");Slider(value:$scene.tilesAcross,in:16...60).accessibilityLabel("Tiles across table")}
                }
                NativeMinimap(scene:scene)
            }.padding(.horizontal,8)
        }
    }
}

/// Shared menu content; each presentation owns its window and popup lifecycle.
struct TableGameMenu:View {
    @ObservedObject var model:TableScapeModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    var body:some View {
        GamePanels(session:model.session,assets:model.scene.assets,immersive:model.immersive,volumeOpen:model.volumeOpen,collapsible:true,tableControlsContent:AnyView(TableViewControls(scene:model.scene)),onOpenTableWindow:{
            Task {await model.showTableWindow(open:openWindow,dismiss:dismissWindow,dismissSpace:dismissImmersiveSpace)}
        },onLeaveTable:{
            Task {await model.leaveTable(open:openWindow,dismiss:dismissWindow,dismissSpace:dismissImmersiveSpace)}
        }).frame(width:640)
    }
}

private struct TableViewControls:View {
    @ObservedObject var scene:GameScene
    private let minimumTiles = 16.0
    private let maximumTiles = 60.0
    private func clampedTiles(_ value:Double)->Double { min(maximumTiles,max(minimumTiles,value)) }
    private var zoom:Binding<Double> {
        Binding(get:{minimumTiles+maximumTiles-clampedTiles(scene.tilesAcross)},
                set:{scene.tilesAcross=clampedTiles(minimumTiles+maximumTiles-$0)})
    }
    var body:some View {
        VStack(spacing:12) {
            HStack(spacing:8) {
                Button("Zoom out",systemImage:"minus.magnifyingglass") {
                    scene.tilesAcross=clampedTiles(scene.tilesAcross+4)
                }.labelStyle(.iconOnly).disabled(scene.tilesAcross>=maximumTiles)
                    .accessibilityIdentifier("table.zoom.out")
                Slider(value:zoom,in:minimumTiles...maximumTiles)
                    .accessibilityLabel("Table zoom").accessibilityIdentifier("table.zoom")
                Button("Zoom in",systemImage:"plus.magnifyingglass") {
                    scene.tilesAcross=clampedTiles(scene.tilesAcross-4)
                }.labelStyle(.iconOnly).disabled(scene.tilesAcross<=minimumTiles)
                    .accessibilityIdentifier("table.zoom.in")
            }
            Button("Rotate 90°",systemImage:"arrow.clockwise") {scene.rotateTableClockwise()}
                .accessibilityIdentifier("table.rotate")
                .accessibilityValue("\(scene.tableQuarterTurns*90)°")
        }
    }
}

struct FloatingGameControls:View {
    @ObservedObject var model:TableScapeModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    var body:some View {
        TableGameMenu(model:model)
        .modifier(GamePopupRouter(session:model.session,coordinator:model.popupCoordinator))
        .task {if !model.didStart {openWindow(id:"main",value:"main")};if model.immersive || model.volumeOpen {dismissWindow(id:"main")}}
        .onChange(of:model.immersive){_,active in if active {dismissWindow(id:"main")}}
        .onChange(of:model.volumeOpen){_,active in if active {dismissWindow(id:"main")}}
    }
}
