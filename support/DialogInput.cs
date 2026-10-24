using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Security.Cryptography;

// Explicit, one-shot desktop input for RE2's own foreground game window only.
// No global key hook, focus stealing, process injection, network or crash-dialog clicks.
class DialogInput {
    [StructLayout(LayoutKind.Sequential)] struct Point { public int x,y; }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int l,t,r,b; }
    [StructLayout(LayoutKind.Sequential)] struct Mouse { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct Key { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct Union { [FieldOffset(0)] public Mouse mouse; [FieldOffset(0)] public Key key; }
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint type; public Union data; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd,StringBuilder s,int n);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd,out Rect r);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point p);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr hwnd,ref Point p);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint n,Input[] inputs,int size);
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
    static long Now() { return (long)(DateTime.UtcNow-new DateTime(1970,1,1)).TotalSeconds; }
    static string Validate(string mode,long stamp,long now,string id) {
        if(mode!="mouse" && mode!="enter" && mode!="space") return "unsupported_input";
        if(String.IsNullOrEmpty(id) || id.Length>100) return "invalid_request";
        if(stamp>now+1 || now-stamp>5) return "expired_request";
        return null;
    }
    static Input[] Events(string mode) {
        var a=new Input[2];
        if(mode=="mouse") { a[0].data.mouse.flags=2; a[1].data.mouse.flags=4; }
        else { for(int i=0;i<2;i++){a[i].type=1;a[i].data.key.scan=(ushort)(mode=="enter"?0x1c:0x39);a[i].data.key.flags=(uint)(8+(i==1?2:0));} }
        return a;
    }
    static string WindowPolicy(string expected,string actual,string process,string windowClass,bool mainWindow) {
        if(!process.Equals("re2",StringComparison.OrdinalIgnoreCase) || !expected.Equals(actual,StringComparison.OrdinalIgnoreCase))return "game_not_foreground";
        if(windowClass=="#32770" || !mainWindow)return "modal_or_non_game_window_rejected";
        return null;
    }
    static string Dispatch(string game,string mode) {
        IntPtr w=GetForegroundWindow(); uint pid; GetWindowThreadProcessId(w,out pid);
        if(w==IntPtr.Zero || pid==0) return "game_not_foreground";
        using(var p=Process.GetProcessById((int)pid)) {
            var c=new StringBuilder(128);GetClassName(w,c,128);
            string blocked=WindowPolicy(Path.Combine(game,"re2.exe"),Path.GetFullPath(p.MainModule.FileName),p.ProcessName,c.ToString(),w==p.MainWindowHandle);
            if(blocked!=null)return blocked;
        }
        Rect r; if(!GetClientRect(w,out r) || r.r-r.l<100 || r.b-r.t<100) return "invalid_game_window";
        foreach(int k in new[]{0x10,0x11,0x12,0x5b,0x5c,1,2}) if(GetAsyncKeyState(k)<0) return "release_desktop_buttons";
        if(mode=="mouse") {
            Point p;if(!GetCursorPos(out p) || !ScreenToClient(w,ref p) || p.x<0 || p.y<0 || p.x>=r.r || p.y>=r.b) return "cursor_outside_game";
        }
        // Recheck focus at the last possible moment; never activate a window ourselves.
        if(GetForegroundWindow()!=w) return "focus_changed";
        Input[] a=Events(mode);
        int size=Marshal.SizeOf(typeof(Input));uint down=SendInput(1,new[]{a[0]},size),up=0;
        try { if(down==1)Thread.Sleep(80); }
        finally { up=SendInput(1,new[]{a[1]},size); }
        return down==1 && up==1?"input_sent":"input_blocked";
    }
    static int Main(string[] args) {
        if(args.Length==1 && args[0]=="--self-test") {
            if(Marshal.SizeOf(typeof(Input))!=(IntPtr.Size==8?40:28))return 2;
            if(Validate("mouse",100,101,"a")!=null || Validate("mouse",90,100,"a")!="expired_request" || Validate("bad",100,100,"a")!="unsupported_input")return 3;
            var a=Events("mouse");var k=Events("enter");
            if(a[0].data.mouse.flags!=2 || a[1].data.mouse.flags!=4 || k[0].data.key.scan!=0x1c || k[1].data.key.flags!=10)return 4;
            if(WindowPolicy("game/re2.exe","game/re2.exe","re2","#32770",true)==null || WindowPolicy("game/re2.exe","other/re2.exe","re2","via",true)==null || WindowPolicy("game/re2.exe","game/re2.exe","re2","via",false)==null || WindowPolicy("game/re2.exe","game/re2.exe","re2","via",true)!=null)return 5;
            Console.WriteLine("PASS input structure/events, expiry, modes, foreground-path and modal-window policy; SendInput NOT called");return 0;
        }
        if(args.Length==2 && args[0]=="--test-belt")return BeltOverlay.SelfTest(args[1]);
        if(args.Length!=2 || args[0]!="--location")return 1;
        try {
            var loc=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(args[1]));
            string game=Path.GetFullPath((string)loc["gamePath"]);
            if(!File.Exists(Path.Combine(game,"re2.exe")))return 1;
            string hash=BitConverter.ToString(SHA256.Create().ComputeHash(Encoding.UTF8.GetBytes(game.ToLowerInvariant()))).Replace("-","");
            bool owner;using(var mutex=new Mutex(true,"Local\\RE2IVR_Dialog_"+hash,out owner)) {
                if(!owner)return 0;
                string data=Path.Combine(game,"reframework","data");Directory.CreateDirectory(data);
                using(var belt=new BeltOverlay(data,game)) {
                string request=Path.Combine(data,"re2ivr_desktop_request.json"),status=Path.Combine(data,"re2ivr_input_bridge.json");
                DateTime last=File.GetLastWriteTimeUtc(request),start=DateTime.UtcNow,lastGame=start,heartbeat=DateTime.MinValue;
                string result="ready",rid="";bool seen=false;
                while(true) {
                    if((DateTime.UtcNow-heartbeat).TotalSeconds>=5) {
                        File.WriteAllText(status,Json.Serialize(new{schema=1,time=Now(),status=result,request=rid}));heartbeat=DateTime.UtcNow;
                        bool alive=false;
                        foreach(var p in Process.GetProcessesByName("re2"))using(p){try{if(Path.GetFullPath(p.MainModule.FileName).Equals(Path.Combine(game,"re2.exe"),StringComparison.OrdinalIgnoreCase))alive=true;}catch{}}
                        if(alive){seen=true;lastGame=DateTime.UtcNow;}
                        if((seen && (DateTime.UtcNow-lastGame).TotalSeconds>10) || (!seen && (DateTime.UtcNow-start).TotalMinutes>3))break;
                    }
                    try {
                        DateTime changed=File.GetLastWriteTimeUtc(request);
                        if(changed!=last && File.Exists(request) && new FileInfo(request).Length<=2048) {
                            var q=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(request));
                            string mode=(string)q["mode"],id=(string)q["id"];long stamp=Convert.ToInt64(q["time"]);
                            last=changed;if(id==rid)continue;rid=id;
                            result=Validate(mode,stamp,Now(),id);
                            if(result==null)result=Dispatch(game,mode);
                            File.WriteAllText(status,Json.Serialize(new{schema=1,time=Now(),status=result,request=rid}));
                        }
                    }catch{result="request_or_window_unavailable";}
                    Thread.Sleep(100);
                }
                }
            }
        }catch{return 1;}
        return 0;
    }
}
