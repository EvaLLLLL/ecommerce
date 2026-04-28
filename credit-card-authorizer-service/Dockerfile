# Stage 1: Build
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY . .
RUN mvn -pl common,credit-card-authorizer-service -am package -DskipTests -q

# Stage 2: Runtime
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /app/credit-card-authorizer-service/target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
