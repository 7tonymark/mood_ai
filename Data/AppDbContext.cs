using Microsoft.EntityFrameworkCore;
using Mood.API.Models;

namespace Mood.API.Data
{
    public class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
        {
        }

        public DbSet<User> Users => Set<User>();
        public DbSet<Couple> Couples => Set<Couple>();
        public DbSet<Nudge> Nudges => Set<Nudge>();
    }
}
