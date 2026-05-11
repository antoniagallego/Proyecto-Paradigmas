ThisBuild / version      := "1.0.0"
ThisBuild / scalaVersion := "2.13.12"

name := "ground"

val akkaVersion     = "2.8.5"
val akkaHttpVersion = "10.5.3"

libraryDependencies ++= Seq(
    "com.typesafe.akka"  %% "akka-actor-typed"     % akkaVersion,
    "com.typesafe.akka"  %% "akka-stream"          % akkaVersion,
    "com.typesafe.akka"  %% "akka-http"            % akkaHttpVersion,
    "com.typesafe.akka"  %% "akka-http-spray-json" % akkaHttpVersion,
    "io.spray"           %% "spray-json"           % "1.3.6",
    "mysql"               % "mysql-connector-java" % "8.0.33",
    "ch.qos.logback"      % "logback-classic"      % "1.4.11"
)

assembly / mainClass       := Some("com.kepler.ground.GroundApp")
assembly / assemblyJarName := "ground-assembly.jar"

assembly / assemblyMergeStrategy := {
    case PathList("META-INF", _*) => MergeStrategy.discard
    case "reference.conf"         => MergeStrategy.concat
    case _                        => MergeStrategy.first
}
