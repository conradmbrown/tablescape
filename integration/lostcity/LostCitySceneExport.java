package local.scape;

import jagex3.client.Client;
import jagex3.dash3d.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Copies Lost City OS1's decoded scene on its render thread, then writes detached JSON. */
public final class LostCitySceneExport {
 private static final String output=System.getProperty("scape.output","");
 private static final String session=UUID.randomUUID().toString();
 private static final AtomicBoolean busy=new AtomicBoolean();
 private static final ExecutorService writer=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"lostcity-tabletop-writer");t.setDaemon(true);return t;});
 private static long last=0,sequence=0;
 private final Map<Integer,List<Double>> batches=new TreeMap<>();
 private final Set<Sprite> seen=Collections.newSetFromMap(new IdentityHashMap<Sprite,Boolean>());
 private final double ox,oz,oy;
 private int faces=0,objects=0,tiles=0;
 private LostCitySceneExport(){ox=Math.floor(Client.localPlayer.x/128.0)*128;oz=Math.floor(Client.localPlayer.z/128.0)*128;oy=Client.getAvH(Client.localPlayer.x,Client.localPlayer.z,Client.minusedlevel);}
 public static void capture(){
  if(output.isEmpty()||Client.state!=30||Client.world==null||Client.localPlayer==null||busy.get())return;
  long now=System.currentTimeMillis();if(now-last<1000)return;last=now;
  try{
   LostCitySceneExport e=new LostCitySceneExport();e.read();if(e.faces==0)return;
   final long seq=++sequence;busy.set(true);
   writer.submit(()->{try{e.publish(seq);}catch(Exception ex){System.err.println("LOSTCITY_EXPORT_ERROR "+ex);}finally{busy.set(false);}});
  }catch(Exception ex){System.err.println("LOSTCITY_CAPTURE_ERROR "+ex);}
 }
 private static int rgb(int colour,int texture){
  if(texture>=0&&Pix3D.textureManager!=null)colour=Pix3D.textureManager.getAverageRgb(texture);
  if(colour<0||colour>=65536)return 0x777777;
  return Pix3D.colourTable[colour];
 }
 private void tri(double[] a,double[] b,double[] c,int rgb){
  if(faces>=80000)return;
  // Quantize only material color to limit engine sections; preserve mesh geometry.
  rgb=rgb&0xF8F8F8;
  List<Double> v=batches.computeIfAbsent(rgb,k->new ArrayList<>());
  for(double[] p:new double[][]{a,b,c}){v.add((p[0]-ox)/128);v.add((p[2]-oz)/128);v.add((oy-p[1])/128);}
  faces++;
 }
 private void read(){
  World w=Client.world;int level=Client.minusedlevel,cx=(int)ox/128,cz=(int)oz/128;
  for(int x=Math.max(0,cx-12);x<=Math.min(w.maxTileX-1,cx+12);x++)for(int z=Math.max(0,cz-12);z<=Math.min(w.maxTileZ-1,cz+12);z++){
   Square s=w.squares[level][x][z];if(s==null)continue;tiles++;
   int[][] h=w.groundh[s.originalLevel];QuickGround q=s.quickGround;
   if(q!=null&&q.colourNE!=12345678){double[] sw={x*128,h[x][z],z*128},se={(x+1)*128,h[x+1][z],z*128},ne={(x+1)*128,h[x+1][z+1],(z+1)*128},nw={x*128,h[x][z+1],(z+1)*128};tri(sw,se,nw,rgb(q.colourSW,q.texture));tri(se,ne,nw,rgb(q.colourNE,q.texture));}
   Ground g=s.ground;if(g!=null)for(int i=0;i<g.faceVertexA.length;i++){if(g.faceColourA[i]==12345678)continue;int a=g.faceVertexA[i],b=g.faceVertexB[i],c=g.faceVertexC[i];tri(new double[]{g.vertexX[a],g.vertexY[a],g.vertexZ[a]},new double[]{g.vertexX[b],g.vertexY[b],g.vertexZ[b]},new double[]{g.vertexX[c],g.vertexY[c],g.vertexZ[c]},rgb(g.faceColourA[i],g.faceTexture==null?-1:g.faceTexture[i]));}
   Wall wall=s.wall;if(wall!=null){model(wall.modelA,wall.x,wall.y,wall.z,0);model(wall.modelB,wall.x,wall.y,wall.z,0);}
   GroundDecor gd=s.groundDecor;if(gd!=null)model(gd.model,gd.x,gd.y,gd.z,0);
   Decor d=s.decor;if(d!=null){model(d.model,d.x+d.xof,d.y,d.z+d.zof,0);model(d.model2,d.x,d.y,d.z,0);}
   for(int i=0;i<s.spriteCount;i++){Sprite p=s.sprites[i];if(p!=null&&seen.add(p))model(p.model,p.x,p.y,p.z,p.yaw);}
  }
 }
 private void model(ModelSource source,int x,int y,int z,int yaw){
  if(source==null)return;ModelLit m=source instanceof ModelLit?(ModelLit)source:source.getTempModel();if(m==null)return;objects++;
  double sin=Math.sin(yaw*Math.PI/1024),cos=Math.cos(yaw*Math.PI/1024);double[][] points=new double[m.numPoints][3];
  for(int i=0;i<m.numPoints;i++)points[i]=new double[]{x+m.pointX[i]*cos+m.pointZ[i]*sin,y+m.pointY[i],z+m.pointZ[i]*cos-m.pointX[i]*sin};
  for(int i=0;i<m.numFaces;i++){if(m.faceColourC[i]==-2||(m.faceAlpha!=null&&(m.faceAlpha[i]&255)>192))continue;int texture=m.faceTextureId==null?-1:m.faceTextureId[i];tri(points[m.faceVertexA[i]],points[m.faceVertexB[i]],points[m.faceVertexC[i]],rgb(m.faceColourA[i],texture));}
 }
 private void publish(long seq)throws Exception{
  StringBuilder b=new StringBuilder(4_000_000);b.append("{\"schema\":1,\"source\":\"LOSTCITY OS1 local server - decoded game geometry\",\"session\":\"").append(session).append("\",\"sequence\":").append(seq).append(",\"meshes\":[");boolean first=true;
  for(Map.Entry<Integer,List<Double>> e:batches.entrySet()){
   if(!first)b.append(',');first=false;int c=e.getKey();List<Double> v=e.getValue();b.append("{\"id\":\"material-").append(c).append("\",\"color\":[").append(((c>>16)&255)/255.0).append(',').append(((c>>8)&255)/255.0).append(',').append((c&255)/255.0).append("],\"vertices\":[");
   for(int i=0;i<v.size();i++){if(i>0)b.append(',');b.append(v.get(i));}b.append("],\"triangles\":[");
   // Both sides retained for initial axis/winding inspection.
   for(int i=0;i<v.size()/3;i+=3){if(i>0)b.append(',');b.append(i).append(',').append(i+1).append(',').append(i+2).append(',').append(i).append(',').append(i+2).append(',').append(i+1);}b.append("]}");
  }
  b.append("]}");byte[] bytes=b.toString().getBytes(StandardCharsets.UTF_8);if(bytes.length>16000000||batches.size()>4096)throw new IllegalStateException("scene budget exceeded");
  Path p=Paths.get(output);if(!p.isAbsolute())throw new IllegalArgumentException("output must be absolute");Files.createDirectories(p.getParent());Path t=Files.createTempFile(p.getParent(),"lostcity-scene-",".tmp");try{Files.write(t,bytes);Files.move(t,p,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(t);}
  if(seq<=3||seq%30==0)System.out.println("LOSTCITY_EXPORTED sequence="+seq+" tiles="+tiles+" objects="+objects+" faces="+faces+" bytes="+bytes.length);
 }
}
