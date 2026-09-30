#include "ScapeMode.h"
#include "ProceduralMeshComponent.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "GameFramework/PlayerController.h"
#include "Engine/DirectionalLight.h"
#include "Components/DirectionalLightComponent.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UnrealClient.h"
#include "InputCoreTypes.h"
void AScapeHUD::DrawHUD(){ Super::DrawHUD(); if(auto* M=Cast<AScapeMode>(GetWorld()->GetAuthGameMode())) { DrawRect(FLinearColor(0.02,0.03,0.04,0.9),16,16,1248,90); DrawText(TEXT("SCAPE / TABLETOP — ENGINE PROTOTYPE"),FLinearColor(1,0.8,0.4),30,24,nullptr,1.3); DrawText(M->Status,FLinearColor::White,30,53); DrawText(TEXT("Middle drag / arrows: orbit   Wheel: zoom   WASD: pan   |   No game commands or headset connection"),FLinearColor::White,30,78); } }
AScapeMode::AScapeMode(){ PrimaryActorTick.bCanEverTick=true; DefaultPawnClass=nullptr; HUDClass=AScapeHUD::StaticClass(); }
void AScapeMode::BeginPlay(){ Super::BeginPlay(); Smoke=FParse::Param(FCommandLine::Get(),TEXT("ScapeSmoke"));
 ScenePath=FPaths::ProjectDir()/TEXT("data/scene.json"); FParse::Value(FCommandLine::Get(),TEXT("ScapeScene="),ScenePath);
 FParse::Value(FCommandLine::Get(),TEXT("ScapeRadius="),Radius); Radius=FMath::Clamp(Radius,100.f,2000.f);
 Camera=GetWorld()->SpawnActor<ACameraActor>(); Camera->GetCameraComponent()->FieldOfView=50; UpdateCamera();
 auto* L=GetWorld()->SpawnActor<ADirectionalLight>(FVector(0,0,700),FRotator(-60,-30,0)); L->GetLightComponent()->SetIntensity(4);
 if(auto* P=GetWorld()->GetFirstPlayerController()){ P->SetViewTarget(Camera); P->bShowMouseCursor=true; }
 if(!LoadScene() && Smoke) FPlatformMisc::RequestExitWithStatus(false,2);
}
bool AScapeMode::LoadScene(){
 FString Text; TSharedPtr<FJsonObject> J;
 if(!FFileHelper::LoadFileToString(Text,*ScenePath)||Text.Len()>16000000||!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),J)||!J.IsValid()) return false;
 double Schema,Seq; FString S,Source; const TArray<TSharedPtr<FJsonValue>>* Meshes;
 if(!J->TryGetNumberField(TEXT("schema"),Schema)||Schema!=1||!J->TryGetNumberField(TEXT("sequence"),Seq)||!FMath::IsFinite(Seq)||Seq<0||FMath::FloorToDouble(Seq)!=Seq||!J->TryGetStringField(TEXT("session"),S)||S.IsEmpty()||!J->TryGetStringField(TEXT("source"),Source)||!J->TryGetArrayField(TEXT("meshes"),Meshes)||Meshes->Num()<1||Meshes->Num()>4096)return false;
 if(S==Session&&Seq<=Sequence)return true;
 struct FData {TArray<FVector> V;TArray<int32> I;FLinearColor Color;}; TArray<FData> Data; int32 Total=0;
 for(auto& M:*Meshes){ const TSharedPtr<FJsonObject>* O; const TArray<TSharedPtr<FJsonValue>> *V,*I,*C;
  if(!M->TryGetObject(O)||!(*O)->TryGetArrayField(TEXT("vertices"),V)||!(*O)->TryGetArrayField(TEXT("triangles"),I)||!(*O)->TryGetArrayField(TEXT("color"),C)||V->Num()%3||I->Num()%3||C->Num()!=3||V->Num()<9||I->Num()<3||(Total+=V->Num())>1500000)return false;
  FData D; for(int32 k=0;k<V->Num();k+=3){double X,Y,Z;if(!(*V)[k]->TryGetNumber(X)||!(*V)[k+1]->TryGetNumber(Y)||!(*V)[k+2]->TryGetNumber(Z)||!FMath::IsFinite(X)||!FMath::IsFinite(Y)||!FMath::IsFinite(Z)||FMath::Abs(X)>512||FMath::Abs(Y)>512||FMath::Abs(Z)>512)return false; D.V.Add(FVector(X,Y,Z)*20);}
  for(auto& Id:*I){double N;if(!Id->TryGetNumber(N)||!FMath::IsFinite(N)||N<0||N>=D.V.Num()||FMath::FloorToDouble(N)!=N)return false;D.I.Add((int32)N);}
  double R,G,B;if(!(*C)[0]->TryGetNumber(R)||!(*C)[1]->TryGetNumber(G)||!(*C)[2]->TryGetNumber(B)||!FMath::IsFinite(R)||!FMath::IsFinite(G)||!FMath::IsFinite(B)||R<0||R>1||G<0||G>1||B<0||B>1)return false;D.Color=FLinearColor(R,G,B);Data.Add(MoveTemp(D));
 }
 for(auto A:MeshActors)if(A)A->Destroy();MeshActors.Empty();
 for(auto& D:Data){auto* A=GetWorld()->SpawnActor<AActor>();auto* P=NewObject<UProceduralMeshComponent>(A);A->SetRootComponent(P);P->RegisterComponent();P->CreateMeshSection_LinearColor(0,D.V,D.I,TArray<FVector>(),TArray<FVector2D>(),TArray<FLinearColor>(),TArray<FProcMeshTangent>(),false);
 auto* Mat=UMaterialInstanceDynamic::Create(LoadObject<UMaterialInterface>(nullptr,TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial")),A);if(Mat){Mat->SetVectorParameterValue(TEXT("Color"),D.Color);P->SetMaterial(0,Mat);}MeshActors.Add(A);}
 Session=S;Sequence=Seq;Status=FString::Printf(TEXT("%s | %d meshes | frame %.0f | desktop viewer; no headset connection"),*Source,Data.Num(),Seq);UE_LOG(LogTemp,Display,TEXT("SCAPE_ACCEPTED session=%s sequence=%.0f meshes=%d"),*S,Seq,Data.Num());return true;
}
void AScapeMode::UpdateCamera(){const float Y=FMath::DegreesToRadians(Yaw),P=FMath::DegreesToRadians(Pitch);FVector V(Radius*FMath::Cos(P)*FMath::Cos(Y),Radius*FMath::Cos(P)*FMath::Sin(Y),Radius*FMath::Sin(P));Camera->SetActorLocation(Pivot+V);Camera->SetActorRotation((-V).Rotation());}
void AScapeMode::Tick(float D){Super::Tick(D);Elapsed+=D;Poll+=D;if(Poll>1){Poll=0;if(!LoadScene())Status=TEXT("Invalid/unavailable scene; last valid frame retained");}
 if(auto* P=GetWorld()->GetFirstPlayerController()){float X,Y;P->GetInputMouseDelta(X,Y);if(P->IsInputKeyDown(EKeys::MiddleMouseButton)){Yaw+=X*.4;Pitch=FMath::Clamp(Pitch+Y*.4f,15.f,85.f);}if(P->IsInputKeyDown(EKeys::Left))Yaw-=D*45;if(P->IsInputKeyDown(EKeys::Right))Yaw+=D*45;if(P->IsInputKeyDown(EKeys::Up))Pitch=FMath::Min(85.f,Pitch+D*35);if(P->IsInputKeyDown(EKeys::Down))Pitch=FMath::Max(15.f,Pitch-D*35);if(P->WasInputKeyJustPressed(EKeys::MouseScrollUp))Radius=FMath::Max(100.f,Radius-40);if(P->WasInputKeyJustPressed(EKeys::MouseScrollDown))Radius=FMath::Min(2000.f,Radius+40);if(P->IsInputKeyDown(EKeys::W))Pivot.X-=D*100;if(P->IsInputKeyDown(EKeys::S))Pivot.X+=D*100;if(P->IsInputKeyDown(EKeys::A))Pivot.Y+=D*100;if(P->IsInputKeyDown(EKeys::D))Pivot.Y-=D*100;}
 if(Smoke&&Elapsed>4&&Shot==0){FScreenshotRequest::RequestScreenshot(FPaths::ProjectSavedDir()/TEXT("scape-angle1.png"),false,false);Shot=1;}if(Smoke&&Elapsed>6&&Shot==1){Yaw=140;Pitch=70;Shot=2;}if(Smoke&&Elapsed>8&&Shot==2){FScreenshotRequest::RequestScreenshot(FPaths::ProjectSavedDir()/TEXT("scape-angle2.png"),false,false);Shot=3;}if(Smoke&&Elapsed>10){UE_LOG(LogTemp,Display,TEXT("SCAPE_SMOKE_PASSED meshes=%d"),MeshActors.Num());FPlatformMisc::RequestExit(false);}UpdateCamera();
}
