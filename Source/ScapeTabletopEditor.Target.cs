using UnrealBuildTool;
public class ScapeTabletopEditorTarget : TargetRules {
 public ScapeTabletopEditorTarget(TargetInfo Target) : base(Target) { Type=TargetType.Editor; DefaultBuildSettings=BuildSettingsVersion.V7; IncludeOrderVersion=EngineIncludeOrderVersion.Unreal5_8; ExtraModuleNames.Add("ScapeTabletop"); }
}
