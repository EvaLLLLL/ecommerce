# Stage 1: Build
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY . .
RUN mvn -pl common,warehouse-service -am package -DskipTests -q

# Stage 2: Runtime
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /app/warehouse-service/target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
