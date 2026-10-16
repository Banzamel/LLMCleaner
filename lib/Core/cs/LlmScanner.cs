using System;
using System.IO;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public class LlmFolder { public string Path; public long Bytes; public long Files; public DateTime LastWrite; }
public class LlmFile { public string Path; public long Bytes; public DateTime LastWrite; }
public class LlmResult { public List<LlmFolder> Folders = new List<LlmFolder>(); public List<LlmFile> Files = new List<LlmFile>(); public long Bytes; public long FileCount; public int Denied; }
public static class LlmScanner {
    static long counter;
    public static long Counter { get { return Interlocked.Read(ref counter); } }
    const FileAttributes Cloud = (FileAttributes)0x400000 | (FileAttributes)0x40000 | FileAttributes.Offline;
    public static Task<LlmResult> Start(string root, int maxDepth, long minFolder, long minFile) {
        Interlocked.Exchange(ref counter, 0);
        return Task.Run(() => {
            var r = new LlmResult(); long n; DateTime o;
            r.Bytes = Scan(new DirectoryInfo(root), 0, maxDepth, minFolder, minFile, r, out n, out o);
            r.FileCount = n;
            return r;
        });
    }
    static long Scan(DirectoryInfo d, int depth, int maxDepth, long minFolder, long minFile, LlmResult r, out long files, out DateTime lastWrite) {
        long total = 0; files = 0; lastWrite = DateTime.MinValue;
        FileSystemInfo[] items;
        try { items = d.GetFileSystemInfos(); } catch { r.Denied++; return 0; }
        foreach (var e in items) {
            try {
                if ((e.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                var sd = e as DirectoryInfo;
                if (sd != null) {
                    long p; DateTime o;
                    total += Scan(sd, depth + 1, maxDepth, minFolder, minFile, r, out p, out o);
                    files += p; if (o > lastWrite) lastWrite = o;
                    continue;
                }
                var f = (FileInfo)e;
                if ((f.Attributes & Cloud) != 0) continue;
                long b = f.Length; DateTime t = f.LastWriteTime;
                total += b; files++; Interlocked.Increment(ref counter);
                if (t > lastWrite) lastWrite = t;
                if (b >= minFile) r.Files.Add(new LlmFile { Path = f.FullName, Bytes = b, LastWrite = t });
            } catch { }
        }
        if (depth >= 1 && depth <= maxDepth && total >= minFolder)
            r.Folders.Add(new LlmFolder { Path = d.FullName, Bytes = total, Files = files, LastWrite = lastWrite });
        return total;
    }
}
