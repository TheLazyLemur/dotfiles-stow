# Project Architecture & Development Guide

## Architecture Principles

### Clean Architecture / Hexagonal Architecture

The project follows clean architecture with clear separation of concerns:

1. **Core Domain Layer**
   - Pure business logic with no external dependencies
   - Defines interfaces for all external interactions
   - Contains domain entities, business rules, and use cases
   - All dependencies point inward toward the core

2. **Infrastructure Layer**
   - Repository implementations for data persistence
   - HTTP handlers for API endpoints
   - Message queue producers and consumers
   - External service integrations

3. **Dependency Inversion**
   - Core defines interfaces, infrastructure implements them
   - Enables testing and swapping implementations
   - No direct dependencies from core to infrastructure

## Testing Philosophy & Structure

### Testing Strategy

The project follows a **pragmatic testing pyramid**:

1. **Unit Tests (Core/Business Logic Layer)**
   - Test business logic in isolation
   - Mock ALL external dependencies
   - Fast execution (milliseconds)
   - Focus on behavior, not implementation

2. **Integration Tests (Infrastructure Layer)**
   - Test with REAL dependencies where possible
   - Use testcontainers for databases
   - No mocking of database interactions
   - Verify actual SQL queries and transactions

3. **End-to-End Tests (API/Handler Layer)**
   - Full HTTP request/response cycle
   - Real database with testcontainers
   - Mock only external services
   - Test complete workflows

### Test Patterns by Layer

#### 1. Core/Business Logic Tests (Unit Tests)
**Characteristics:**
- Standard Go table-driven tests
- Mock ALL dependencies using hand-written mocks
- Test pure business logic

```go
func TestBusinessFunction(t *testing.T) {
    tests := []struct {
        name    string
        input   Input
        want    Output
        wantErr error
    }{
        {
            name:    "valid input",
            input:   Input{Field: "value"},
            want:    Output{Result: "expected"},
            wantErr: nil,
        },
        {
            name:    "invalid input",
            input:   Input{Field: ""},
            want:    Output{},
            wantErr: ValidationError{},
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // given
            mockRepo := &MockRepository{}
            mockRepo.On("GetById", mock.Any).Return(mockEntity, nil)

            // when
            got, err := BusinessFunction(mockRepo, tt.input)

            // then
            if tt.wantErr != nil {
                if err == nil || err != tt.wantErr {
                    t.Errorf("BusinessFunction() error = %v, wantErr %v", err, tt.wantErr)
                }
                return
            }
            if err != nil {
                t.Errorf("BusinessFunction() unexpected error = %v", err)
                return
            }
            if !reflect.DeepEqual(got, tt.want) {
                t.Errorf("BusinessFunction() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

#### 2. Database/Repository Tests (Integration Tests)
**Characteristics:**
- Use real database via testcontainers
- Standard table-driven tests
- NO mocking of database operations

```go
func TestRepositoryCreate(t *testing.T) {
    // Setup test database
    ctx := context.Background()
    dbContainer, err := testcontainers.NewPostgreSQLContainer(ctx)
    if err != nil {
        t.Fatal(err)
    }
    defer dbContainer.Terminate(ctx)
    
    connStr, err := dbContainer.ConnectionString(ctx, "sslmode=disable")
    if err != nil {
        t.Fatal(err)
    }
    
    db, err := sql.Open("postgres", connStr)
    if err != nil {
        t.Fatal(err)
    }
    defer db.Close()
    
    // Run migrations
    if err := runMigrations(db); err != nil {
        t.Fatal(err)
    }
    
    repo := &Repository{db: db}
    
    tests := []struct {
        name    string
        entity  Entity
        wantErr bool
    }{
        {
            name: "valid entity",
            entity: Entity{
                ID:   uuid.New(),
                Name: "test",
            },
            wantErr: false,
        },
        {
            name: "duplicate ID",
            entity: Entity{
                ID:   existingID,
                Name: "test",
            },
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // given
            // ... setup test data if needed
            
            // when
            result, err := repo.Create(tt.entity)
            
            // then
            if tt.wantErr {
                if err == nil {
                    t.Error("Repository.Create() expected error, got nil")
                }
                return
            }
            if err != nil {
                t.Errorf("Repository.Create() unexpected error = %v", err)
                return
            }
            
            // Verify result
            if result.ID != tt.entity.ID {
                t.Errorf("Repository.Create() ID = %v, want %v", result.ID, tt.entity.ID)
            }
        })
    }
}
```

#### 3. API Handler Tests (Integration Tests)
**Characteristics:**
- Use real database with testcontainers
- Standard table-driven tests
- Mock only external services

```go
func TestHandlerCreateEntity(t *testing.T) {
    // Setup test database and handler
    ctx := context.Background()
    dbContainer, db := setupTestDB(t, ctx)
    defer dbContainer.Terminate(ctx)
    defer db.Close()
    
    repo := &Repository{db: db}
    mockExternalClient := &MockExternalClient{}
    handler := &Handler{
        repo:           repo,
        externalClient: mockExternalClient,
    }
    
    tests := []struct {
        name           string
        requestBody    string
        setupMocks     func(*MockExternalClient)
        wantStatusCode int
        wantResponse   string
    }{
        {
            name:        "valid request",
            requestBody: `{"name": "test", "amount": 100}`,
            setupMocks: func(mock *MockExternalClient) {
                mock.On("Validate", mock.Any).Return(nil)
            },
            wantStatusCode: http.StatusCreated,
            wantResponse:   `{"id":`,
        },
        {
            name:        "invalid request",
            requestBody: `{"name": "", "amount": -1}`,
            setupMocks: func(mock *MockExternalClient) {
                // No external call expected
            },
            wantStatusCode: http.StatusBadRequest,
            wantResponse:   `{"error":`,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // given
            tt.setupMocks(mockExternalClient)
            
            req := httptest.NewRequest("POST", "/entities", strings.NewReader(tt.requestBody))
            req.Header.Set("Content-Type", "application/json")
            w := httptest.NewRecorder()
            
            // when
            handler.CreateEntity(w, req)
            
            // then
            if w.Code != tt.wantStatusCode {
                t.Errorf("Handler.CreateEntity() status = %v, want %v", w.Code, tt.wantStatusCode)
            }
            
            if !strings.Contains(w.Body.String(), tt.wantResponse) {
                t.Errorf("Handler.CreateEntity() body = %v, want to contain %v", w.Body.String(), tt.wantResponse)
            }
        })
    }
}
```

### Given-When-Then Test Structure

All tests follow the **Given-When-Then** pattern for clarity:

```go
func TestFunction(t *testing.T) {
    // given
    // ... setup test data and mocks
    input := Input{Field: "value"}
    mockDep := &MockDependency{}
    mockDep.On("Method", input).Return(expectedResult, nil)

    // when
    // ... execute the action being tested
    result, err := FunctionUnderTest(mockDep, input)

    // then
    // ... assert expected outcomes
    if err != nil {
        t.Errorf("unexpected error: %v", err)
    }
    if result != expected {
        t.Errorf("got %v, want %v", result, expected)
    }
}
```

### Test Execution Strategy

Separate tests by type using build tags:

```go
//go:build unit
// +build unit

func TestUnitTest(t *testing.T) {
    // Unit test with mocked dependencies
}
```

```go
//go:build integration
// +build integration

func TestIntegrationTest(t *testing.T) {
    // Integration test with real dependencies
}
```

Run tests separately:
```bash
# Unit tests only - fast, mocked dependencies
go test -tags=unit ./...

# Integration tests only - slower, real dependencies  
go test -tags=integration ./...
```

### Key Testing Principles

1. **Real Dependencies Where Possible**
   - Database tests use real databases
   - Migrations run in tests
   - Actual queries executed
   - Catches real-world issues

2. **Table-Driven Tests**
   - Use test scenarios for multiple cases
   - Standard Go idiom
   - Easy to add new test cases
   - Clear test documentation

3. **Test Isolation**
   - Each test function is independent
   - Clean up after tests
   - No shared state between tests
   - Use t.Cleanup() for cleanup

4. **Deterministic Tests**
   - Mock time/clock for consistent results
   - Control external dependencies
   - No flaky tests

## Code Structure Patterns

### Repository Pattern
- All database operations through repositories
- Return domain models, not database rows
- Define interfaces in core, implement in infrastructure
- Example:
```go
type Repository interface {
    GetById(id uuid.UUID) (*Entity, error)
    Create(entity Entity) (Entity, error)
}
```

### Service/Use Case Pattern
- Business logic in domain services
- Orchestrate repositories and external calls
- No direct database access
- Single responsibility per service

### Interface-First Design
- Define interfaces in the core/domain layer
- Infrastructure implements interfaces
- Enables easy mocking and testing

### Error Handling
- Custom error types for domain errors
- Include context in errors
- Example:
```go
type NotFoundError struct {
    EntityType string
    ID         string
}

func (e NotFoundError) Error() string {
    return fmt.Sprintf("%s with ID %s not found", e.EntityType, e.ID)
}
```

## Comment Structure

### Philosophy: Self-Documenting Code
- Code should be clear without comments
- Comments explain "why" not "what"
- Use meaningful names

### Comment Patterns

1. **Given-When-Then in Tests**
   ```go
   // given
   // ... test setup
   
   // when
   // ... action
   
   // then
   // ... assertions
   ```

2. **Continuation Indicators**
   ```go
   // ... additional setup
   // ... required mocks
   ```

3. **TODO Comments**
   - Must be actionable
   - Format: `// TODO: description`

4. **Complex Logic Only**
   - Explain non-obvious algorithms
   - Reference external documentation

## Development Best Practices

### Testing Approach
1. Write unit tests for business logic with mocks
2. Write integration tests for repositories with real databases
3. Write handler tests for APIs with real databases, mock external services
4. Use table-driven tests for multiple scenarios
5. Follow Given-When-Then structure

### Database Guidelines
1. Use testcontainers for integration tests
2. Run actual migrations in tests
3. Clean up test data between tests
4. Test both success and error cases

### Code Organization
1. Keep business logic in core/domain layer
2. Define interfaces in core, implement in infrastructure
3. Use dependency injection
4. Handle errors with custom types

This approach ensures maintainability, testability, and follows standard Go testing idioms.