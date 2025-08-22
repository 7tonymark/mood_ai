namespace Mood.API.Models;

public class Couple
{
    public Guid Id { get; set; }

    // Existing: link to users
    public Guid User1Id { get; set; }
    public Guid User2Id { get; set; }

    // Optional for MVP: store partner names
    public string User1Name { get; set; } = string.Empty;
    public string User2Name { get; set; } = string.Empty;

    // Optional: timestamp for creation
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation properties (EF Core)
    public User? User1 { get; set; }
    public User? User2 { get; set; }

    public ICollection<Answer>? Answers { get; set; }
}
