# Multi-stage: Render (and any amd64 CI builder) compiles the jar in the first
# stage, so nothing needs to be built on the host beforehand.
#
# Note: building this stage under QEMU emulation on Apple Silicon fails while
# Maven unpacks itself. Build natively, or let Render do it.

FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN chmod +x mvnw && ./mvnw -q dependency:go-offline
COPY src src
RUN ./mvnw -q -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/server-*.jar app.jar
ENV PORT=8080
# Leave headroom for metaspace and native buffers inside the container limit.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0"
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
