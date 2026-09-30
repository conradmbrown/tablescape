#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/HUD.h"
#include "ScapeMode.generated.h"
UCLASS()
class SCAPETABLETOP_API AScapeHUD : public AHUD { GENERATED_BODY() public: virtual void DrawHUD() override; };
UCLASS()
class SCAPETABLETOP_API AScapeMode : public AGameModeBase {
 GENERATED_BODY()
 public: AScapeMode(); virtual void BeginPlay() override; virtual void Tick(float Delta) override; FString Status=TEXT("Waiting for scene");
 private: bool LoadScene(); void UpdateCamera();
 UPROPERTY() TObjectPtr<class ACameraActor> Camera;
 UPROPERTY() TArray<TObjectPtr<class AActor>> MeshActors;
 FString ScenePath; FVector Pivot=FVector::ZeroVector; float Yaw=45,Pitch=52,Radius=650,Elapsed=0,Poll=0; int32 Shot=0; bool Smoke=false;
 double Sequence=-1; FString Session;
};
