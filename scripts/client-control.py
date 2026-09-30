#!/usr/bin/env python3
"""Control the running native Unity client, through its private local command spool."""
import argparse,json,os,pathlib,time,uuid,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def request(command,directory,timeout=12):
    directory=pathlib.Path(directory)
    marker=directory/'client.json'
    if not marker.exists():raise RuntimeError('Unity client control is not running')
    pid=json.loads(marker.read_text())['pid']
    try:os.kill(pid,0)
    except ProcessLookupError:raise RuntimeError('Unity client control is stale; restart the client')
    command={**command,'pid':pid}
    key=f'{time.time_ns():020d}-{uuid.uuid4().hex}.json'
    final=directory/'requests'/key;temp=final.with_suffix('.tmp');response=directory/'responses'/key
    temp.write_text(json.dumps(command));temp.chmod(0o600);temp.rename(final)
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if response.exists():
            result=json.loads(response.read_text());response.unlink()
            if not result.get('ok'):raise RuntimeError(result.get('error','Client command failed'))
            return result
        time.sleep(.05)
    # Never resend automatically: a timed-out action may already have executed.
    raise TimeoutError('Client command timed out; inspect state before retrying')
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',default=str(ROOT/'Saved/client-control'))
    sub=parser.add_subparsers(dest='command',required=True)
    sub.add_parser('state');sub.add_parser('logout');sub.add_parser('capture')
    near=sub.add_parser('nearby');near.add_argument('--name');near.add_argument('--operation');near.add_argument('--radius',type=float,default=16)
    act=sub.add_parser('act');act.add_argument('key');act.add_argument('operation')
    act=sub.add_parser('chop');act.add_argument('key',help='Exact nearby tree key (see nearby --operation Chop-down)')
    button=sub.add_parser('button');button.add_argument('id',type=int)
    action=sub.add_parser('action');action.add_argument('json',help='Native action JSON; ordinary server gameplay validation still applies')
    camera=sub.add_parser('camera');camera.add_argument('yaw',type=float);camera.add_argument('pitch',type=float);camera.add_argument('distance',type=float)
    args=parser.parse_args();cmd={'command':args.command}
    if args.command=='nearby':cmd={'command':'state'}
    elif args.command in ('act','chop'):cmd={'command':'act','key':args.key,'operation':'Chop-down' if args.command=='chop' else args.operation}
    elif args.command=='button':cmd['id']=args.id
    elif args.command=='action':cmd['action']=json.loads(args.json)
    elif args.command=='camera':cmd.update(yaw=args.yaw,pitch=args.pitch,distance=args.distance)
    result=request(cmd,args.directory)
    if args.command=='nearby':
        result=[{'key':t['key'],'kind':t['kind'],'name':t['actor']['name'],'x':t['actor']['x'],'z':t['actor']['z'],'distance':round(t['distance'],1),'visible':t['visible'],'operations':t['actor'].get('ops',[])} for t in result['nearby'] if t['distance']<=args.radius and t['kind']!='visual' and (not args.name or t['actor']['name'].casefold()==args.name.casefold()) and (not args.operation or args.operation.casefold().replace('-','').replace(' ','') in [o.casefold().replace('-','').replace(' ','') for o in t['actor'].get('ops',[]) if o])]
    print(json.dumps(result,indent=2))
if __name__=='__main__':
    try:main()
    except Exception as e:print(str(e),file=sys.stderr);sys.exit(1)
