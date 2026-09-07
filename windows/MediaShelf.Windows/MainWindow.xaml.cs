using System.Collections.ObjectModel;
using System.Windows.Data;
using System.Windows.Input;
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
    private readonly ArtworkMatcher _artworkMatcher;
    private Dictionary<string,string> _roots;
    private List<LibraryFolder> _libraries = new();
    private List<MediaItem> _media = new();
    private MediaItem? _selectedCard;
    private MediaItem? _featured;
    private MediaItem? SelectedCard => _selectedCard;
    private MediaItem? SelectedPlayable => EpisodesList.SelectedItem as MediaItem ?? SelectedCard;

    public MainWindow(PortablePaths paths, LibraryDatabase database)
    {
        InitializeComponent(); _paths=paths; _database=database; _artworkMatcher=new ArtworkMatcher(paths); _roots=paths.LoadWindowsRoots();
        Loaded += (_,_) => Bootstrap(); Closed += (_,_) => _paths.SaveWindowsRoots(_roots);
    }

    private void Bootstrap()
    {
        try { _database.Initialize(); Reload(); }
        catch(Exception error) { ShowError("Could not open the portable library", error); }
    }

    private void Reload()
    {
        _libraries=_database.Libraries(); _media=_database.AllMedia(); foreach(var item in _media) item.ResolvedPosterPath=_paths.ResolvePortableAsset(item.PosterPath); ApplyFilters();
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
        var visible=cards.OrderBy(x=>x.Kind=="episode" ? 1 : 0).ToList();
        var previousPlayable=SelectedPlayable?.Id;
        var previous=_selectedCard?.Id;
        var previousShow=_selectedCard?.Kind=="episode" ? _selectedCard.DisplayTitle : null;
        var view=new ListCollectionView(visible);
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(MediaItem.SectionTitle)));
        LibraryList.ItemsSource=view;
        BrowseHeading.Text=filter=="All" ? "My Library" : filter;
        EmptyMessage.Visibility=visible.Count==0 ? Visibility.Visible : Visibility.Collapsed;
        var continuing=LibraryPresentation.ContinueWatching(_media);
        ContinueList.ItemsSource=continuing;
        ContinueSection.Visibility=filter=="All" && query.Length==0 && continuing.Count>0 ? Visibility.Visible : Visibility.Collapsed;
        _featured=continuing.FirstOrDefault() ?? visible.FirstOrDefault();
        HeroTitle.Text=_featured?.DisplayTitle ?? "Your next movie night starts here.";
        HeroSummary.Text=_featured?.Summary ?? (_featured is null ? "Add a folder to bring your movies and shows together." : "Your movies. Your drive. Your private streaming service.");
        HeroImage.Source=LoadImage(_featured?.BackdropPath);
        HeroPlay.Visibility=HeroDetails.Visibility=_featured is null ? Visibility.Collapsed : Visibility.Visible;
        HeroAdd.Visibility=_featured is null ? Visibility.Visible : Visibility.Collapsed;
        HeroPlay.Content=_featured?.PlaybackPosition>0 ? "▶  Resume" : "▶  Play";
        _selectedCard=visible.FirstOrDefault(x=>x.Id==previous) ?? visible.FirstOrDefault(x=>x.Kind=="episode" && x.DisplayTitle.Equals(previousShow,StringComparison.OrdinalIgnoreCase));
        if(_selectedCard is not null && DetailPanel.Visibility==Visibility.Visible) ShowDetails(_selectedCard, false, previousPlayable);
        else { DetailPanel.Visibility=Visibility.Collapsed; BrowseContent.IsEnabled=true; EpisodesList.ItemsSource=null; }

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
        try { var warnings=new List<string>(); var candidates=_scanner.Scan(library.Id,root,warnings.Add); _database.Ingest(library.Id,candidates); Reload(); _ = EnrichArtworkAsync(); if(warnings.Count>0)StatusText.Text+=$" · {warnings.Count} warnings"; }
        catch(Exception error){ShowError($"Could not scan {library.DisplayName}",error);}
    }
    private async Task EnrichArtworkAsync()
    {
        StatusText.Text="Finding missing artwork…";
        await _artworkMatcher.EnrichAsync(_database, _media);
        await Dispatcher.InvokeAsync(Reload);
        StatusText.Text += " · artwork updated";
    }
    private async void GetMissingArtwork_Click(object sender, RoutedEventArgs e)
    {
        if (_media.Count == 0) { StatusText.Text = "Add a media folder first."; return; }
        StatusText.Text = "Finding missing artwork…";
        await _artworkMatcher.EnrichAsync(_database, _media);
        Reload();
        StatusText.Text = "Artwork search complete. Manual artwork and ambiguous matches were left unchanged.";
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

    private BitmapImage? LoadImage(string? storedPath)
    {
        var path=_paths.ResolvePortableAsset(storedPath);
        if(path is null)return null;
        try { var image=new BitmapImage(); image.BeginInit(); image.CacheOption=BitmapCacheOption.OnLoad; image.UriSource=new Uri(Path.GetFullPath(path)); image.EndInit(); image.Freeze(); return image; }
        catch { return null; }
    }

    private void ShowDetails(MediaItem item, bool open=true, string? preferredEpisodeId=null)
    {
        _selectedCard=item;
        DetailTitle.Text=item.DisplayTitle;
        var episodes=item.Kind=="episode" ? Episodes(item).ToList() : new List<MediaItem>();
        DetailMeta.Text=item.Kind=="episode" ? $"TV Show · {episodes.Count} episodes" : $"{item.Year?.ToString()??"Movie"} · {item.Genre??""}";
        DetailSummary.Text=item.Summary??"No description available.";
        PosterImage.Source=LoadImage(item.PosterPath);
        SeasonBox.ItemsSource=episodes.Select(x=>x.SeasonNumber??0).Distinct().Select(x=>$"Season {x}").ToList();
        var resume=episodes.FirstOrDefault(x=>x.Id==preferredEpisodeId)
            ?? episodes.FirstOrDefault(x=>x.Id==item.Id && x.PlaybackPosition>0 && !x.IsWatched)
            ?? episodes.Where(x=>x.PlaybackPosition>0 && !x.IsWatched).OrderByDescending(x=>x.SeasonNumber).ThenByDescending(x=>x.EpisodeNumber).FirstOrDefault()
            ?? episodes.FirstOrDefault(x=>!x.IsWatched) ?? episodes.FirstOrDefault();
        SeasonBox.SelectedItem=resume is null ? null : $"Season {resume.SeasonNumber??0}";
        EpisodesList.SelectedItem=resume;
        EpisodesHeading.Visibility=SeasonBox.Visibility=EpisodesList.Visibility=episodes.Count>0 ? Visibility.Visible : Visibility.Collapsed;
        UpdatePlaybackButtons();
        if(open) { DetailPanel.Visibility=Visibility.Visible; BrowseContent.IsEnabled=false; DetailPanel.UpdateLayout(); PlayButton.Focus(); }
    }
    private void UpdatePlaybackButtons()
    {
        if(PlayButton is null)return;
        var item=SelectedPlayable;
        PlayButton.IsEnabled=FavoriteButton.IsEnabled=RestartButton.IsEnabled=item is not null;
        PlayButton.Content=item?.PlaybackPosition>0 && !item.IsWatched ? "▶  Resume" : "▶  Play";
        FavoriteButton.Content=item?.IsFavorite==true ? "Unfavorite" : "Favorite";
    }
    private void Season_Changed(object sender,SelectionChangedEventArgs e)
    {
        if(SelectedCard is null || EpisodesList is null)return;
        var season=SeasonBox.SelectedItem?.ToString();
        EpisodesList.ItemsSource=Episodes(SelectedCard).Where(x=>$"Season {x.SeasonNumber??0}"==season).ToList();
        EpisodesList.SelectedIndex=EpisodesList.Items.Count>0 ? 0 : -1;
    }
    private void Episode_Changed(object sender,SelectionChangedEventArgs e)=>UpdatePlaybackButtons();
    private void LibraryList_SelectionChanged(object sender,SelectionChangedEventArgs e)
    { if(LibraryList.SelectedItem is MediaItem item) _selectedCard=item; }
    private void ContinueList_SelectionChanged(object sender,SelectionChangedEventArgs e)
    { if(ContinueList.SelectedItem is MediaItem item) _selectedCard=item; }
    private void Card_Open(object sender,RoutedEventArgs e)
    { if((sender as ListView)?.SelectedItem is MediaItem item)ShowDetails(item); }
    private void HeroDetails_Click(object sender,RoutedEventArgs e) {if(_featured is not null)ShowDetails(_featured);}
    private void HeroPlay_Click(object sender,RoutedEventArgs e) {if(_featured is null)return;ShowDetails(_featured);Play_Click(sender,e);}
    private void Sidebar_Click(object sender,RoutedEventArgs e)=>Sidebar.Visibility=Sidebar.Visibility==Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    private void CloseDetails_Click(object sender,RoutedEventArgs e) {DetailPanel.Visibility=Visibility.Collapsed;BrowseContent.IsEnabled=true;LibraryList.Focus();}
    private void Window_KeyDown(object sender,KeyEventArgs e)
    {
        if(e.Key==Key.Escape) {if(DetailPanel.Visibility==Visibility.Visible)CloseDetails_Click(sender,e);else Sidebar.Visibility=Visibility.Collapsed;e.Handled=true;}
        else if(e.Key==Key.Enter && DetailPanel.Visibility!=Visibility.Visible && (LibraryList.IsKeyboardFocusWithin || ContinueList.IsKeyboardFocusWithin) && SelectedCard is not null) {ShowDetails(SelectedCard);e.Handled=true;}
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
