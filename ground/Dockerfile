FROM sbtscala/scala-sbt:eclipse-temurin-17_1.9.7_2.13.12 AS builder

WORKDIR /app
COPY build.sbt project/plugins.sbt ./
RUN mkdir project && echo 'addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.1.5")' > project/plugins.sbt
RUN sbt update

COPY src ./src
RUN sbt assembly

FROM eclipse-temurin:17-jre-slim
WORKDIR /app
COPY --from=builder /app/target/scala-2.13/ground-assembly.jar app.jar
COPY src/main/resources/init.sql /app/init.sql

EXPOSE 8003

CMD ["java", "-jar", "app.jar"]
