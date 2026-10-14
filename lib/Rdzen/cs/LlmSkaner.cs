using System;
using System.IO;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public class LlmFolder { public string Sciezka; public long Bajty; public long Pliki; public DateTime Ostatnio; }
public class LlmPlik { public string Sciezka; public long Bajty; public DateTime Ostatnio; }
public class LlmWynik { public List<LlmFolder> Foldery = new List<LlmFolder>(); public List<LlmPlik> Pliki = new List<LlmPlik>(); public long Bajty; public long LiczbaPlikow; public int Odmowy; }
public static class LlmSkaner {
    static long licznik;
    public static long Licznik { get { return Interlocked.Read(ref licznik); } }
    const FileAttributes Chmura = (FileAttributes)0x400000 | (FileAttributes)0x40000 | FileAttributes.Offline;
    public static Task<LlmWynik> Start(string root, int maxGlebokosc, long minFolder, long minPlik) {
        Interlocked.Exchange(ref licznik, 0);
        return Task.Run(() => {
            var w = new LlmWynik(); long n; DateTime o;
            w.Bajty = Skanuj(new DirectoryInfo(root), 0, maxGlebokosc, minFolder, minPlik, w, out n, out o);
            w.LiczbaPlikow = n;
            return w;
        });
    }
    static long Skanuj(DirectoryInfo d, int gl, int maxGl, long minFolder, long minPlik, LlmWynik w, out long pliki, out DateTime ostatnio) {
        long suma = 0; pliki = 0; ostatnio = DateTime.MinValue;
        FileSystemInfo[] el;
        try { el = d.GetFileSystemInfos(); } catch { w.Odmowy++; return 0; }
        foreach (var e in el) {
            try {
                if ((e.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                var sd = e as DirectoryInfo;
                if (sd != null) {
                    long p; DateTime o;
                    suma += Skanuj(sd, gl + 1, maxGl, minFolder, minPlik, w, out p, out o);
                    pliki += p; if (o > ostatnio) ostatnio = o;
                    continue;
                }
                var f = (FileInfo)e;
                if ((f.Attributes & Chmura) != 0) continue;
                long b = f.Length; DateTime t = f.LastWriteTime;
                suma += b; pliki++; Interlocked.Increment(ref licznik);
                if (t > ostatnio) ostatnio = t;
                if (b >= minPlik) w.Pliki.Add(new LlmPlik { Sciezka = f.FullName, Bajty = b, Ostatnio = t });
            } catch { }
        }
        if (gl >= 1 && gl <= maxGl && suma >= minFolder)
            w.Foldery.Add(new LlmFolder { Sciezka = d.FullName, Bajty = suma, Pliki = pliki, Ostatnio = ostatnio });
        return suma;
    }
}
