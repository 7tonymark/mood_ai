using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Mood.API.Migrations
{
    /// <inheritdoc />
    public partial class AddCoupleNames : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "CreatedAt",
                table: "Couples",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<string>(
                name: "User1Name",
                table: "Couples",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "User2Name",
                table: "Couples",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateTable(
                name: "Answer",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CoupleId = table.Column<Guid>(type: "uuid", nullable: false),
                    QuestionId = table.Column<Guid>(type: "uuid", nullable: false),
                    AnswerText = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Answer", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Answer_Couples_CoupleId",
                        column: x => x.CoupleId,
                        principalTable: "Couples",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Couples_User1Id",
                table: "Couples",
                column: "User1Id");

            migrationBuilder.CreateIndex(
                name: "IX_Couples_User2Id",
                table: "Couples",
                column: "User2Id");

            migrationBuilder.CreateIndex(
                name: "IX_Answer_CoupleId",
                table: "Answer",
                column: "CoupleId");

            migrationBuilder.AddForeignKey(
                name: "FK_Couples_Users_User1Id",
                table: "Couples",
                column: "User1Id",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_Couples_Users_User2Id",
                table: "Couples",
                column: "User2Id",
                principalTable: "Users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Couples_Users_User1Id",
                table: "Couples");

            migrationBuilder.DropForeignKey(
                name: "FK_Couples_Users_User2Id",
                table: "Couples");

            migrationBuilder.DropTable(
                name: "Answer");

            migrationBuilder.DropIndex(
                name: "IX_Couples_User1Id",
                table: "Couples");

            migrationBuilder.DropIndex(
                name: "IX_Couples_User2Id",
                table: "Couples");

            migrationBuilder.DropColumn(
                name: "CreatedAt",
                table: "Couples");

            migrationBuilder.DropColumn(
                name: "User1Name",
                table: "Couples");

            migrationBuilder.DropColumn(
                name: "User2Name",
                table: "Couples");
        }
    }
}
