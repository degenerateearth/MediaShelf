using System.Windows;
using LibVLCSharp.Shared;

namespace MediaShelf.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        Core.Initialize();
        base.OnStartup(e);
        var paths = PortablePaths.FromExecutable();
        var database = new LibraryDatabase(paths);
        var window = new MainWindow(paths, database);
        MainWindow = window;
        window.Show();
    }
}
