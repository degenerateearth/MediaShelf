using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace MediaShelf.Windows;

public partial class MainWindow : Window
{
    private readonly PortablePaths _paths;
    private readonly LibraryDatabase _database;
    private readonly MediaScanner _scanner = new();
    private Dictionary<string,string> _roots;
    private List<LibraryFolder> _libraries = new();
    private List<MediaItem> _media = new();
    private MediaItem? SelectedCard => LibraryList.SelectedItem as MediaItem;
    private MediaItem? SelectedPlayable => EpisodesList.SelectedItem as MediaItem ?? SelectedCard;

    public MainWindow(PortablePaths paths, LibraryDatabase database)
    {
        InitializeComponent(); _paths=paths; _database=database; _roots=paths.LoadWindowsRoots();
        Loaded += (_,_) => Bootstrap(); Closed += (_,_) => _paths.SaveWindowsRoots(_roots);
    }

    private void Bootstrap()
    {
        try { _database.Initialize(); Reload(); }
        catch(Exception error) { ShowError("Could not open the portable library", error); }
    }

    private void Reload()
    {
        _libraries=_database.Libraries(); _media=_database.AllMedia(); ApplyFilters();
        StatusText.Text=$"{_media.Count} media files · {_libraries.Count} folders · Data: {_paths.Root}";
    }

    private List<MediaItem> Cards()
    {
        var movies=_media.Where(x=>x.Kind=="movie");
        var shows=_media.Where(x=>x.Kind=="episode").GroupBy(x=>x.DisplayTitle,StringComparer.OrdinalIgnoreCase).Select(group=>
        {
            var card=group.OrderBy(x=>x.SeasonNumber??0).ThenBy(x=>x.EpisodeNumber??0).First(); card.EpisodeCountLabel=$"{group.Count()} episodes"; return card;
        });
        return movies.Concat(shows).ToList();
    }

    private void ApplyFilters()
    {
        if(LibraryList is null || FilterBox is null || SortBox is null || SearchBox is null)return;
        IEnumerable<MediaItem> cards=Cards(); var query=SearchBox.Text.Trim();
        if(query.Length>0) cards=cards.Where(x=>Contains(x.DisplayTitle,query)||Contains(x.EpisodeTitle,query)||Contains(x.Genre,query)||(x.Year?.ToString().Contains(query)==true)|| (x.Kind=="episode" && _media.Any(e=>e.DisplayTitle.Equals(x.DisplayTitle,StringComparison.OrdinalIgnoreCase)&&Contains(e.EpisodeTitle,query))));
        var filter=((ComboBoxItem?)FilterBox.SelectedItem)?.Content?.ToString()??"All";
        cards=filter switch { "Movies"=>cards.Where(x=>x.Kind=="movie"), "TV Shows"=>cards.Where(x=>x.Kind=="episode"), "Watched"=>cards.Where(CardWatched), "Unwatched"=>cards.Where(x=>!CardWatched(x)), "Favorites"=>cards.Where(CardFavorite), _=>cards };
        var sort=((ComboBoxItem?)SortBox.SelectedItem)?.Content?.ToString()??"Title";
        cards=sort switch { "Recently Added"=>cards.OrderByDescending(x=>x.DateAdded), "Recently Watched"=>cards.OrderByDescending(x=>x.LastWatched??0), "Year"=>cards.OrderByDescending(x=>x.Year??0), _=>cards.OrderBy(x=>x.SortTitle??x.DisplayTitle,StringComparer.CurrentCultureIgnoreCase) };
        LibraryList.ItemsSource=new ObservableCollection<MediaItem>(cards); if(LibraryList.Items.Count>0)LibraryList.SelectedIndex=0;
    }

    private bool CardWatched(MediaItem x)=>x.Kind=="movie"?x.IsWatched:Episodes(x).Any(e=>e.IsWatched);
    private bool CardFavorite(MediaItem x)=>x.Kind=="movie"?x.IsFavorite:Episodes(x).Any(e=>e.IsFavorite);
    private IEnumerable<MediaItem> Episodes(MediaItem x)=>_media.Where(e=>e.Kind=="episode"&&e.DisplayTitle.Equals(x.DisplayTitle,StringComparison.OrdinalIgnoreCase)).OrderBy(e=>e.SeasonNumber).ThenBy(e=>e.EpisodeNumber);
    private static bool Contains(string? value,string query)=>value?.Contains(query,StringComparison.CurrentCultureIgnoreCase)==true;

    private void AddFolder_Click(object sender,RoutedEventArgs e)
    {
        var dialog=new OpenFolderDialog { Title="Choose a Movies or TV folder",Multiselect=false };
        if(dialog.ShowDialog(this)!=true)return;
        try { var library=_database.AddOrReconnectLibrary(dialog.FolderName); _roots[library.Id]=dialog.FolderName; _paths.SaveWindowsRoots(_roots); Scan(library,dialog.FolderName); }
        catch(Exception error){ShowError("Could not add the folder",error);}
    }

    private void Refresh_Click(object sender,RoutedEventArgs e)
    {
        foreach(var library in _database.Libraries().Where(x=>x.Enabled))
        {
            var root=ResolveRoot(library); if(root is null){StatusText.Text=$"Reconnect {library.DisplayName} with Add folder.";continue;} Scan(library,root);
        }
    }
    private void Scan(LibraryFolder library,string root)
    {
        StatusText.Text=$"Scanning {library.DisplayName}…";
        try { var warnings=new List<string>(); var candidates=_scanner.Scan(library.Id,root,warnings.Add); _database.Ingest(library.Id,candidates); Reload(); if(warnings.Count>0)StatusText.Text+=$" · {warnings.Count} warnings"; }
        catch(Exception error){ShowError($"Could not scan {library.DisplayName}",error);}
    }
    private string? ResolveRoot(LibraryFolder library)
    {
        if(_roots.TryGetValue(library.Id,out var mapped)&&Directory.Exists(mapped))return mapped;
        if(Directory.Exists(library.StoredPath))return library.StoredPath; return null;
    }

    private string? ResolveMedia(MediaItem item)
    {
        var library=_libraries.FirstOrDefault(x=>x.Id==item.LibraryId); var root=library is null?null:ResolveRoot(library);
        if(root is not null){var candidate=Path.Combine(root,item.RelativePath.Replace('/',Path.DirectorySeparatorChar));if(File.Exists(candidate))return candidate;}
        return File.Exists(item.AbsolutePath)?item.AbsolutePath:null;
    }

    private void LibraryList_SelectionChanged(object sender,SelectionChangedEventArgs e)
    {
        var item=SelectedCard;if(item is null)return; DetailTitle.Text=item.DisplayTitle; DetailMeta.Text=item.Kind=="episode"?$"TV Show · {item.EpisodeCountLabel}":$"{item.Year?.ToString()??"Movie"} · {item.Genre??""}"; DetailSummary.Text=item.Summary??"No description available.";
        var poster=_paths.ResolvePortableAsset(item.PosterPath); PosterImage.Source=null; if(poster is not null)try{PosterImage.Source=new BitmapImage(new Uri(poster));}catch{}
        var episodes=item.Kind=="episode"?Episodes(item).ToList():new List<MediaItem>(); EpisodesList.ItemsSource=episodes; EpisodesHeading.Visibility=episodes.Count>0?Visibility.Visible:Visibility.Collapsed; EpisodesList.Visibility=episodes.Count>0?Visibility.Visible:Visibility.Collapsed; if(episodes.Count>0)EpisodesList.SelectedIndex=0;
        FavoriteButton.Content=CardFavorite(item)?"Unfavorite":"Favorite";
    }

    private void Play_Click(object sender,RoutedEventArgs e)
    {
        var item=SelectedPlayable;if(item is null)return;var path=ResolveMedia(item);if(path is null){MessageBox.Show("The media file is unavailable. Reconnect its library folder and refresh.","MediaShelf");return;}
        var queue=item.Kind=="episode"?Episodes(item).ToList():new List<MediaItem>{item}; var player=new PlayerWindow(_database,queue,item,ResolveMedia); player.Owner=this; player.ShowDialog(); Reload();
    }
    private void Favorite_Click(object sender,RoutedEventArgs e){var item=SelectedPlayable;if(item is null)return;_database.SetFavorite(item.Id,!item.IsFavorite);Reload();}
    private void Restart_Click(object sender,RoutedEventArgs e){var item=SelectedPlayable;if(item is null)return;_database.Restart(item.Id);Reload();}
    private void Filters_Changed(object sender,EventArgs e)=>ApplyFilters();
    private void ShowError(string title,Exception error)=>MessageBox.Show($"{title}.\n\n{error.Message}","MediaShelf",MessageBoxButton.OK,MessageBoxImage.Error);
}
