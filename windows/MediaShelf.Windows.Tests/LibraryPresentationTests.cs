using Xunit;
using MediaShelf.Windows;

public class LibraryPresentationTests
{
    [Fact]
    public void CompletingLaterEpisodeDoesNotResurrectEarlierResume()
    {
        var items = new[] {
            new MediaItem { Id="old", Kind="episode", DisplayTitle="Signal", SeasonNumber=1, EpisodeNumber=1, PlaybackPosition=100 },
            new MediaItem { Id="finished", Kind="episode", DisplayTitle="SIGNAL", SeasonNumber=2, EpisodeNumber=1, IsWatched=true },
            new MediaItem { Id="movie", DisplayTitle="Signal", PlaybackPosition=50 }
        };
        Assert.Equal("movie", Assert.Single(LibraryPresentation.ContinueWatching(items)).Id);
    }

    [Fact]
    public void ResumeUsesFurthestEpisodeAndOrdersSeriesByRecency()
    {
        var items = new[] {
            new MediaItem { Id="old", Kind="episode", DisplayTitle="Signal", SeasonNumber=1, EpisodeNumber=2, PlaybackPosition=100, LastWatched=300 },
            new MediaItem { Id="next", Kind="episode", DisplayTitle="Signal", SeasonNumber=2, EpisodeNumber=1, PlaybackPosition=50, LastWatched=200 },
            new MediaItem { Id="movie", PlaybackPosition=50, LastWatched=250 }
        };
        Assert.Equal(new[]{"movie","next"}, LibraryPresentation.ContinueWatching(items).Select(x=>x.Id));
    }
}
