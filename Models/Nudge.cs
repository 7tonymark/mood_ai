namespace Mood.API.Models;
public class Nudge
{
    public Guid Id { get; set; }
    public Guid CoupleId { get; set; }
    public Guid SenderId { get; set; }
    public string Message { get; set; } = null!;
    public bool IsAiGenerated { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}