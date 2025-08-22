namespace Mood.API.Models;
public class Answer
{
    public Guid Id { get; set; }
    public Guid CoupleId { get; set; }
    public Guid QuestionId { get; set; }
    public string? AnswerText { get; set; }
    public DateTime CreatedAt { get; set; }
}
