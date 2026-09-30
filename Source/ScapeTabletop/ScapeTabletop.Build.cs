using UnrealBuildTool;
public class ScapeTabletop : ModuleRules {
 public ScapeTabletop(ReadOnlyTargetRules Target) : base(Target) { PCHUsage=PCHUsageMode.UseExplicitOrSharedPCHs; PublicDependencyModuleNames.AddRange(new string[]{"Core","CoreUObject","Engine","InputCore","Json","ProceduralMeshComponent"}); }
}
