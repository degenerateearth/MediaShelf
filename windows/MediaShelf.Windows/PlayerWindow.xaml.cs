using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using LibVLCSharp.Shared;

namespace MediaShelf.Windows;

public partial class PlayerWindow : Window
{
    private readonly LibraryDatabase _database; private readonly List<MediaItem> _queue; private readonly Func<MediaItem,string?> _resolver;
    private readonly LibVLC _libVlc; private readonly MediaPlayer _player; private readonly DispatcherTimer _timer; private MediaItem _item; private bool _scrubbing;
    public PlayerWindow(LibraryDatabase database,List<MediaItem> queue,MediaItem item,Func<MediaItem,string?> resolver)
    {
        InitializeComponent();_database=database;_queue=queue;_item=item;_resolver=resolver;_libVlc=new LibVLC("--no-video-title-show");_player=new MediaPlayer(_libVlc);Video.MediaPlayer=_player;
        _player.EndReached+=(_,_)=>Dispatcher.Invoke(PlayNext);_timer=new DispatcherTimer{Interval=TimeSpan.FromSeconds(1)};_timer.Tick+=(_,_)=>Tick();Loaded+=(_,_)=>Play(_item);Closing+=(_,_)=>Save();Closed+=(_,_)=>{_timer.Stop();_player.Dispose();_libVlc.Dispose();};
    }
    private void Play(MediaItem item){var path=_resolver(item);if(path is null)return;Save();_item=item;Title=$"{item.DisplayTitle} — MediaShelf";using var media=new Media(_libVlc,new Uri(path));_player.Play(media);if(item.PlaybackPosition>0)_player.Time=(long)(item.PlaybackPosition*1000);_timer.Start();}
    private void Tick(){if(_player.Length<=0)return;if(!_scrubbing){Timeline.Maximum=_player.Length/1000d;Timeline.Value=_player.Time/1000d;}TimeText.Text=$"{TimeSpan.FromMilliseconds(_player.Time):h\\:mm\\:ss} / {TimeSpan.FromMilliseconds(_player.Length):h\\:mm\\:ss}";if(_player.Time>0)_database.UpdateProgress(_item.Id,_player.Time/1000d,_player.Length/1000d);}
    private void Save(){if(_player?.Length>0&&_player.Time>=0)_database.UpdateProgress(_item.Id,_player.Time/1000d,_player.Length/1000d);}
    private void PlayNext(){var index=_queue.FindIndex(x=>x.Id==_item.Id);if(index>=0&&index+1<_queue.Count)Play(_queue[index+1]);else Close();}
    private void PlayPause_Click(object sender,RoutedEventArgs e){_player.Pause();PlayPauseButton.Content=_player.IsPlaying?"Pause":"Play";}
    private void Timeline_Down(object sender,MouseButtonEventArgs e)=>_scrubbing=true;
    private void Timeline_Up(object sender,MouseButtonEventArgs e){_player.Time=(long)(Timeline.Value*1000);_scrubbing=false;}
    private void Window_KeyDown(object sender,KeyEventArgs e){if(e.Key==Key.Space)PlayPause_Click(sender,new RoutedEventArgs());else if(e.Key==Key.Left)_player.Time=Math.Max(0,_player.Time-10000);else if(e.Key==Key.Right)_player.Time=Math.Min(_player.Length,_player.Time+10000);else if(e.Key==Key.Escape)Close();}
}
