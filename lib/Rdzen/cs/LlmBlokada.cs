using System;
using System.Runtime.InteropServices;
public static class LlmBlokada {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateFileW(string path, uint access, uint share, IntPtr sec, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static bool Zablokowany(string path) {
        // DELETE, FILE_SHARE_READ|WRITE|DELETE, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT
        IntPtr h = CreateFileW(@"\\?\" + path, 0x10000, 7, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
        if (h == new IntPtr(-1)) return true;
        CloseHandle(h);
        return false;
    }
}
