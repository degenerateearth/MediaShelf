namespace MediaShelf.Windows.Tests;

using Xunit;

public sealed class CompatibilityTests
{
    [Theory]
    [InlineData("Alien (1979).mkv", "movie", "Alien", 1979, null, null)]
    [InlineData("Dexter S03E11.mkv", "episode", "Dexter", null, 3, 11)]
    [InlineData("Vikings 1x04.mp4", "episode", "Vikings", null, 1, 4)]
    [InlineData("Foundation S02 The Complete Season.mkv", "episode", "Foundation", null, 2, null)]
    public void Parser_matches_mac_contract(string name,string kind,string title,int? year,int? season,int? episode)
    {
        var parsed=new FilenameParser().Parse(name);
        Assert.Equal(kind,parsed.Kind);Assert.Equal(title,parsed.Title);Assert.Equal(year,parsed.Year);Assert.Equal(season,parsed.Season);Assert.Equal(episode,parsed.Episode);
    }

    [Fact]
    public void Stable_id_matches_mac_SHA256_contract()
    {
        var id=MediaScanner.StableId("12345678-1234-1234-1234-123456789ABC","TV/Dexter S01E01.mkv",12345);
        Assert.Equal("b77e62a7004935e6002a1db8065096e1",id);
    }

    [Fact]
    public void Stable_id_normalizes_windows_separators()
    {
        Assert.Equal(MediaScanner.StableId("A","TV/Show.mkv",4),MediaScanner.StableId("A","TV\\Show.mkv",4));
    }
}
