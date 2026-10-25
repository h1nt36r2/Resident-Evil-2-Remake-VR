using System;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Threading;
using System.Runtime.InteropServices;
using Valve.VR;

// Separate compositor client: never creates meshes or changes camera/player transforms in RE2.
class BeltOverlay : IDisposable {
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr LoadLibrary(string name);
    readonly string data,game;readonly JavaScriptSerializer json=new JavaScriptSerializer();
    readonly Dictionary<string,ulong> handles=new Dictionary<string,ulong>();
    readonly Dictionary<string,string> textures=new Dictionary<string,string>();
    volatile bool stop;Thread thread;CVRSystem system;CVROverlay overlays;
    static readonly string[] kinds={"pistol","knife","grenade","flash","ammo","back"};
    static long Now(){return (long)(DateTime.UtcNow-new DateTime(1970,1,1)).TotalSeconds;}
    public BeltOverlay(string data,string game){this.data=data;this.game=game;thread=new Thread(Run);thread.IsBackground=true;thread.Start();}
    static float F(Dictionary<string,object> d,string k){float v=Convert.ToSingle(d[k]);if(float.IsNaN(v)||float.IsInfinity(v)||Math.Abs(v)>2)throw new Exception("Invalid belt coordinate");return v;}
    static GraphicsPath Rounded(float x,float y,float w,float h,float r){var p=new GraphicsPath();p.AddArc(x,y,r*2,r*2,180,90);p.AddArc(x+w-r*2,y,r*2,r*2,270,90);p.AddArc(x+w-r*2,y+h-r*2,r*2,r*2,0,90);p.AddArc(x,y+h-r*2,r*2,r*2,90,90);p.CloseFigure();return p;}
    static void Image(string path,string kind,int count,bool held){
        using(var b=new Bitmap(192,256,PixelFormat.Format32bppArgb))using(var g=Graphics.FromImage(b))
        using(var leather=new SolidBrush(Color.FromArgb(240,61,44,32)))using(var metal=new SolidBrush(count>0?Color.Silver:Color.DimGray))
        using(var white=new SolidBrush(Color.White))using(var gold=new SolidBrush(Color.Goldenrod))
        using(var pen=new Pen(Color.Tan,3))using(var font=new Font(FontFamily.GenericSansSerif,15,FontStyle.Bold)) {
            g.SmoothingMode=SmoothingMode.AntiAlias;g.Clear(Color.Transparent);
            using(var p=Rounded(8,52,176,195,34)){g.FillPath(leather,p);g.DrawPath(pen,p);}
            if(count>0 && !held){
                if(kind=="pistol"||kind=="back"){g.FillRectangle(metal,39,34,117,29);g.FillPolygon(metal,new[]{new Point(100,58),new Point(139,58),new Point(132,147),new Point(94,145)});g.DrawRectangle(pen,59,65,43,35);}
                if(kind=="knife"){g.FillPolygon(metal,new[]{new Point(82,91),new Point(88,1),new Point(112,76),new Point(109,91)});g.FillRectangle(gold,68,91,61,10);g.FillRectangle(metal,85,101,23,74);}
                if(kind=="grenade"){g.FillEllipse(metal,54,71,87,104);g.FillRectangle(gold,77,49,32,26);g.DrawLines(pen,new[]{new Point(87,48),new Point(129,50),new Point(145,104)});g.DrawEllipse(pen,61,40,24,22);}
                if(kind=="flash"){g.FillRectangle(metal,68,65,60,110);g.FillEllipse(metal,68,55,60,20);g.DrawLines(pen,new[]{new Point(84,55),new Point(130,39),new Point(144,90)});}
                if(kind=="ammo")for(int n=0;n<5;n++){g.FillRectangle(gold,34+n*26,85,17,65);g.FillEllipse(metal,34+n*26,72,17,25);}
            }
            g.DrawString(kind, font,white,17,185);g.DrawString(held?"in hand":count.ToString(),font,white,17,215);
            b.Save(path,ImageFormat.Png);
        }
    }
    static HmdMatrix34_t Matrix(HmdMatrix34_t h,float x,float y,float z){
        foreach(float v in new[]{h.m0,h.m1,h.m2,h.m3,h.m4,h.m5,h.m6,h.m7,h.m8,h.m9,h.m10,h.m11})if(float.IsNaN(v)||float.IsInfinity(v)||Math.Abs(v)>10000)throw new Exception("Invalid tracking matrix");
        float rx=h.m0,rz=h.m8,len=(float)Math.Sqrt(rx*rx+rz*rz);if(len<.01f)throw new Exception("Invalid head yaw");rx/=len;rz/=len;
        float px=h.m3+rx*x-rz*z,py=h.m7+y,pz=h.m11+rz*x+rx*z;
        // Face the head, rather than attaching a flat HUD to the user's view.
        float nx=h.m3-px,ny=h.m7-py,nz=h.m11-pz;len=(float)Math.Sqrt(nx*nx+ny*ny+nz*nz);if(len<.05f)throw new Exception("Belt too close");nx/=len;ny/=len;nz/=len;
        float dot=rx*nx+rz*nz;float ax=rx-nx*dot,ay=-ny*dot,az=rz-nz*dot;len=(float)Math.Sqrt(ax*ax+ay*ay+az*az);if(len<.01f)throw new Exception("Invalid belt basis");ax/=len;ay/=len;az/=len;
        return new HmdMatrix34_t{m0=ax,m1=ny*az-nz*ay,m2=nx,m3=px,m4=ay,m5=nz*ax-nx*az,m6=ny,m7=py,m8=az,m9=nx*ay-ny*ax,m10=nz,m11=pz};
    }
    void Status(string status){try{File.WriteAllText(Path.Combine(data,"re2ivr_belt_status.json"),json.Serialize(new{schema=1,time=Now(),status=status}));}catch{}}
    void Hide(){if(overlays!=null)foreach(ulong h in handles.Values)overlays.HideOverlay(h);}
    void Run(){
        try {
            while(!stop){
                try{var p=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(data,"re2ivr_belt.json")));if(Convert.ToBoolean(p["enabled"]) && Math.Abs(Now()-Convert.ToInt64(p["time"]))<3)break;}catch{}
                Thread.Sleep(250);
            }
            if(stop)return;
            if(LoadLibrary(Path.Combine(game,"openvr_api.dll"))==IntPtr.Zero)throw new Exception("OpenVR client library unavailable");
            var error=EVRInitError.None;system=OpenVR.Init(ref error,EVRApplicationType.VRApplication_Overlay);
            if(error!=EVRInitError.None || system==null)throw new Exception("OpenVR overlay init: "+error);
            overlays=OpenVR.Overlay;if(overlays==null)throw new Exception("OpenVR overlay interface unavailable");
            var poses=new TrackedDevicePose_t[OpenVR.k_unMaxTrackedDeviceCount];
            DateTime seen=DateTime.MinValue;Dictionary<string,object> packet=null;long statusAt=0;
            string input=Path.Combine(data,"re2ivr_belt.json"),cache=Path.Combine(data,"re2ivr-belt-cache");Directory.CreateDirectory(cache);
            while(!stop){
                try {
                    DateTime modified=File.GetLastWriteTimeUtc(input);
                    if(modified!=seen && File.Exists(input) && new FileInfo(input).Length<16000){packet=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(input));seen=modified;}
                    if(packet==null || !Convert.ToBoolean(packet["enabled"]) || Math.Abs(Now()-Convert.ToInt64(packet["time"]))>3){Hide();Thread.Sleep(100);continue;}
                    system.GetDeviceToAbsoluteTrackingPose(ETrackingUniverseOrigin.TrackingUniverseStanding,0,poses);
                    if(!poses[0].bPoseIsValid || !poses[0].bDeviceIsConnected){Hide();Thread.Sleep(100);continue;}
                    foreach(object obj in (System.Collections.IEnumerable)packet["slots"]){
                        var row=(Dictionary<string,object>)obj;string kind=(string)row["kind"];if(Array.IndexOf(kinds,kind)<0)continue;
                        int count=Math.Max(0,Math.Min(9999,Convert.ToInt32(row["count"])));bool held=row.ContainsKey("held") && Convert.ToBoolean(row["held"]);
                        ulong handle;if(!handles.TryGetValue(kind,out handle)){
                            var e=overlays.CreateOverlay("re2ivr.belt."+kind+"."+System.Diagnostics.Process.GetCurrentProcess().Id,"RE2IVR "+kind,ref handle);
                            if(e!=EVROverlayError.None)throw new Exception("CreateOverlay: "+e);handles[kind]=handle;overlays.SetOverlayWidthInMeters(handle,kind=="pistol"?.16f:.11f);
                        }
                        string key=count+":"+held;
                        if(!textures.ContainsKey(kind)||textures[kind]!=key){string path=Path.Combine(cache,kind+".png");Image(path,kind,count,held);var e=overlays.SetOverlayFromFile(handle,path);if(e!=EVROverlayError.None)throw new Exception("Overlay texture: "+e);textures[kind]=key;}
                        var m=Matrix(poses[0].mDeviceToAbsoluteTracking,F(row,"x"),F(row,"y"),F(row,"z"));
                        var transformError=overlays.SetOverlayTransformAbsolute(handle,ETrackingUniverseOrigin.TrackingUniverseStanding,ref m);
                        var showError=overlays.ShowOverlay(handle);
                        if(transformError!=EVROverlayError.None || showError!=EVROverlayError.None)throw new Exception("Overlay transform/show rejected");
                    }
                    if(Now()!=statusAt){Status("SteamVR belt active: "+handles.Count+" spatial icon overlays");statusAt=Now();}
                }catch(Exception e){Hide();Status("Belt suspended: "+e.Message);Thread.Sleep(500);}
                Thread.Sleep(50);
            }
        }catch(Exception e){Status("Belt unavailable: "+e.Message);}
        finally{if(overlays!=null)foreach(ulong h in handles.Values)try{overlays.DestroyOverlay(h);}catch{};if(system!=null)OpenVR.Shutdown();}
    }
    public void Dispose(){stop=true;if(thread!=null)thread.Join(1500);}
    public static int SelfTest(string folder){
        var packet=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>("{\"slots\":[{\"kind\":\"pistol\"}]}");if(!(packet["slots"] is System.Collections.IEnumerable))return 7;
        var h=new HmdMatrix34_t{m0=1,m5=1,m10=1,m7=1.7f};var m=Matrix(h,.23f,-.7f,.04f);
        if(Math.Abs(m.m3-.23f)>.0001 || Math.Abs(m.m7-1)>.0001 || Math.Abs(m.m11-.04f)>.0001)return 6;
        double norm=m.m0*m.m0+m.m4*m.m4+m.m8*m.m8;if(Math.Abs(norm-1)>.0001)return 8;
        h.m0=float.NaN;try{Matrix(h,0,-.6f,0);return 9;}catch(InvalidOperationException){return 10;}catch(Exception){}
        Directory.CreateDirectory(folder);foreach(string k in kinds)Image(Path.Combine(folder,k+".png"),k,3,false);
        Console.WriteLine("PASS spatial belt transform and rounded item textures; no OpenVR runtime started");return 0;
    }
}
