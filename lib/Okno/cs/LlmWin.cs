using System;
using System.Runtime.InteropServices;
namespace LlmWin {
    [ComImport, Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eee6f"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ITaskbarList3 {
        void HrInit(); void AddTab(IntPtr h); void DeleteTab(IntPtr h); void ActivateTab(IntPtr h); void SetActiveAlt(IntPtr h);
        void MarkFullscreenWindow(IntPtr h, [MarshalAs(UnmanagedType.Bool)] bool f);
        void SetProgressValue(IntPtr h, ulong done, ulong total);
        void SetProgressState(IntPtr h, int flags);
    }
    [ComImport, Guid("56FDF344-FD6D-11d0-958A-006097C9A090"), ClassInterface(ClassInterfaceType.None)]
    class TaskbarList { }
    public static class Natywne {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("gdi32.dll")] static extern int GetDeviceCaps(IntPtr dc, int i);
        // DPI ekranu wedlug GDI - to samo, czego uzywa rysowanie tekstu (LOGPIXELSX = 88)
        public static int DpiEkranu() {
            IntPtr dc = GetDC(IntPtr.Zero);
            try { return GetDeviceCaps(dc, 88); } finally { ReleaseDC(IntPtr.Zero, dc); }
        }
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string id);
        static ITaskbarList3 pasek;
        // stan: 0 brak, 1 nieokreslony, 2 normalny, 4 blad
        public static void PostepNaPasku(IntPtr h, int stan, ulong ile, ulong z) {
            try {
                if (pasek == null) { pasek = (ITaskbarList3)new TaskbarList(); pasek.HrInit(); }
                pasek.SetProgressState(h, stan);
                if (stan == 2 || stan == 4) { pasek.SetProgressValue(h, ile, z); }
            } catch { }
        }
        public static void CiemnyPasekTytulu(IntPtr h) {
            int tak = 1;
            if (DwmSetWindowAttribute(h, 20, ref tak, 4) != 0) { DwmSetWindowAttribute(h, 19, ref tak, 4); }
        }
    }
}
