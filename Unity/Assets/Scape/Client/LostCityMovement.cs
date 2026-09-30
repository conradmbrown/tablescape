using System;
using System.Collections.Generic;
using UnityEngine;
namespace Scape.Client {
// All actors share one server-tick timeline. A small playout buffer absorbs polling
// jitter; new snapshots never restart a journey from its partly rendered position.
public sealed class LostCityMovementClock {
    const double TickSeconds=.6,BufferTicks=1.3;
    readonly Queue<double> phases=new Queue<double>();
    int originTick,lastTick;double originTime,targetTime,lastTime;bool initialized;
    public void Observe(int tick,double now){
        if(!initialized||tick<lastTick||tick-lastTick>8){
            initialized=true;originTick=lastTick=tick;originTime=targetTime=lastTime=now;phases.Clear();
        }
        if(tick==lastTick&&phases.Count>0)return;
        lastTick=tick;phases.Enqueue(now-(tick-originTick)*TickSeconds);
        while(phases.Count>32)phases.Dequeue();
        targetTime=double.MaxValue;foreach(double phase in phases)targetTime=Math.Min(targetTime,phase);
    }
    public double At(double now){
        double dt=Math.Max(0,now-lastTime);lastTime=now;
        // Slowly correct clock drift, never jump an actor at packet arrival.
        originTime+=Math.Max(-dt*.02,Math.Min(dt*.02,targetTime-originTime));
        return originTick+(now-originTime)/TickSeconds-BufferTicks;
    }
}
public sealed class LostCityMovementTrack {
    struct Sample {public int tick;public Vector3 position;}
    readonly List<Sample> samples=new List<Sample>();
    public bool Moving{get;private set;}public bool Running{get;private set;}
    public Vector3 Direction{get;private set;}
    public bool Add(Vector3 position,int tick,bool snap){
        if(samples.Count>0&&tick<samples[samples.Count-1].tick&&!snap)return false;
        bool reset=snap||samples.Count==0;
        if(!reset){var last=samples[samples.Count-1];reset=tick-last.tick>8||Vector3.Distance(last.position,position)>8;}
        if(reset){samples.Clear();Moving=Running=false;Direction=Vector3.zero;}
        if(samples.Count>0&&samples[samples.Count-1].tick==tick)return false;
        samples.Add(new Sample{tick=tick,position=position});
        if(samples.Count>32)samples.RemoveAt(0);
        return reset;
    }
    public Vector3 Evaluate(double tick){
        while(samples.Count>2&&tick>=samples[1].tick)samples.RemoveAt(0);
        Moving=false;if(samples.Count==0)return Vector3.zero;
        var a=samples[0];if(samples.Count==1||tick<=a.tick)return a.position;
        var b=samples[1];
        if(tick>=b.tick)return b.position; // Stop at confirmed state; never walk through an obstacle on a guess.
        Vector3 delta=b.position-a.position;Direction=new Vector3(delta.x,0,delta.z);
        Moving=Direction.sqrMagnitude>.00001f;
        if(Moving)Running=Mathf.Max(Mathf.Abs(delta.x),Mathf.Abs(delta.z))/(b.tick-a.tick)>1.5f;
        return Vector3.Lerp(a.position,b.position,(float)((tick-a.tick)/(b.tick-a.tick)));
    }
}
public sealed partial class LostCityClient {
    LostCityMovementClock movementClock=new LostCityMovementClock();
    public double MovementTick=>movementClock.At(Time.unscaledTimeAsDouble);
}
}
