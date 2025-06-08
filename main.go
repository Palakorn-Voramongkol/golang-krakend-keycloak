package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v4"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var (
	mongoClient *mongo.Client
	mongoDB     *mongo.Database
)

// --- NEW HELPER FUNCTION ---
// Manually parse the JWT from the Authorization header without validation
func parseToken(c *fiber.Ctx) (jwt.MapClaims, error) {
	authHeader := c.Get("Authorization")
	if authHeader == "" {
		return nil, fmt.Errorf("missing Authorization header")
	}

	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		return nil, fmt.Errorf("invalid Authorization header format")
	}
	tokenString := parts[1]

	// Parse the token without verifying the signature. We trust KrakenD for that.
	token, _, err := new(jwt.Parser).ParseUnverified(tokenString, jwt.MapClaims{})
	if err != nil {
		return nil, fmt.Errorf("failed to parse token: %v", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return nil, fmt.Errorf("invalid token claims")
	}
	return claims, nil
}

// --- MODIFIED HELPER ---
// extract roles from parsed claims
func extractRoles(claims jwt.MapClaims) ([]string, error) {
	// Keycloak now puts roles in a top-level "roles" claim
	if rolesClaim, ok := claims["roles"].([]interface{}); ok {
		var out []string
		for _, r := range rolesClaim {
			if s, ok2 := r.(string); ok2 {
				out = append(out, s)
			}
		}
		return out, nil
	}
	return nil, fmt.Errorf("no roles in token")
}

// --- MODIFIED MIDDLEWARE ---
// Middleware to allow only users with a specific role
func requireRole(role string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		claims, err := parseToken(c)
		if err != nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": err.Error()})
		}

		roles, err := extractRoles(claims)
		if err != nil {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{"error": "Cannot extract roles"})
		}
		for _, r := range roles {
			if r == role {
				// Store claims in context for the next handler to use
				c.Locals("claims", claims)
				return c.Next()
			}
		}
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{"error": fmt.Sprintf("Missing role: %s", role)})
	}
}

// Connect to MongoDB
func initMongo() {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	clientOptions := options.Client().ApplyURI(mongoURI)
	client, err := mongo.Connect(ctx, clientOptions)
	if err != nil {
		log.Fatal("Mongo Connect error:", err)
	}
	if err = client.Ping(ctx, nil); err != nil {
		log.Fatal("Mongo Ping error:", err)
	}
	mongoClient = client
	dbName := os.Getenv("MONGO_DB")
	if dbName == "" {
		dbName = "demo_db"
	}
	mongoDB = client.Database(dbName)
	log.Println("Connected to MongoDB:", mongoURI)
}

func main() {
	initMongo()

	app := fiber.New()

	// Public route (no auth)
	app.Get("/public", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"message": "This is a public endpoint."})
	})

	// Protected route: any authenticated user
	app.Get("/profile", func(c *fiber.Ctx) error {
		claims, err := parseToken(c)
		if err != nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": err.Error()})
		}
		username, _ := claims["preferred_username"].(string)

		return c.JSON(fiber.Map{
			"message":  fmt.Sprintf("Hello, %v", username),
			"roles":    claims["roles"],
			"subject":  claims["sub"],
			"issuedAt": claims["iat"],
		})
	})

	// Protected route: only users with realm role "user"
	app.Get("/user", requireRole("user"), func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"message": "Hello, user-level endpoint!"})
	})

	// Protected route: only users with realm role "admin"
	app.Get("/admin", requireRole("admin"), func(c *fiber.Ctx) error {
		count, err := mongoDB.Collection("items").CountDocuments(context.Background(), struct{}{})
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Database error"})
		}
		return c.JSON(fiber.Map{
			"message":     "Hello, admin-level endpoint!",
			"itemCountDB": count,
		})
	})

	log.Println("Starting server on port 3000")
	log.Fatal(app.Listen(":3000"))
}
