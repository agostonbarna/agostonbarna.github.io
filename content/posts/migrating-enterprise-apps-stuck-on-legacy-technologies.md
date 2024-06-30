---
title: "Migrating enterprise apps stuck on legacy technologies"
date: 2024-06-30
draft: false
---

Enterprise applications often have a hefty and complex code base, mission-critical functionality, and a constant influx of feature demands that can result in a slower pace of dependency updates and a tendency to lag behind. This situation can worsen over time, as certain high-profile dependencies become outdated or discontinued, preventing the update of interlocked dependencies and leading to a cascade of technological stagnation. Eventually, this can reach a critical point, requiring big bang migrations to break free from the constraints of problematic legacy technologies.

I recently had the opportunity to bring an enterprise application back from this state. In this blog post, I'll provide an overview of the migration process, the notable challenges, and the tools that helped automate the repetitive parts of the migration.

{{< toc >}}

## Migration-supporting tools

### OpenRewrite

OpenRewrite is an automated source code refactoring tool focused primarily on JVM languages such as Java, Groovy, Kotlin. It provides pre-built [recipes](https://docs.openrewrite.org/recipes) for common migration scenarios - e.g. upgrading popular frameworks and libraries, such as Spring, JUnit, Mockito, and migrating between different technologies - reducing the migration time by a significant amount.

OpenRewrite provides [Gradle](https://docs.openrewrite.org/running-recipes/running-rewrite-on-a-gradle-project-without-modifying-the-build) and [Maven](https://docs.openrewrite.org/running-recipes/running-rewrite-on-a-maven-project-without-modifying-the-build) plugins [that run locally, without uploading the processed data to any cloud](https://docs.openrewrite.org/reference/faq#does-openrewrite-collect-any-data-from-our-projects). Also, JetBrains recently added a [plugin to IntelliJ that makes it easier to create and run OpenRewrite recipes](https://www.jetbrains.com/help/idea/openrewrite.html).

Some things to keep in mind when using OpenRewrite:
* OpenRewrite uses [Lossless Semantic Trees (LSTs)](https://docs.openrewrite.org/concepts-explanations/lossless-semantic-trees) under the hood, which unlike traditional Abstract Syntax Trees (ASTs), allow precise and minimally invasive changes to the source code without removing the comments, messing up the formatting, and blowing up the diff in the code reviews.
* It builds up the LST in each run, which is a rather expensive operation and can take some time. Therefore, if we want to save time, we should use composite recipes (either prebuilt or custom combinations) instead of running each recipe individually to reduce the overhead. On the other hand, it's easier to review smaller chunks of changes, so we have to make a trade-off depending on the situation.
* It must fit the entire LST in RAM, so with a larger project we may run out of memory with the default Gradle memory limit (AFAIK 512MB). In this case we can try to increase the memory limits of the JVM process by passing the `-Dorg.gradle.jvmargs=-Xmx4G` flag to Gradle. The [Moderne CLI doesn't have this limitation](https://docs.openrewrite.org/reference/faq#im-getting-java.lang.outofmemoryerror-java-heap-space-when-running-openrewrite), but it requires a license for commercial use, and it may upload data to the Moderne cloud!

### IntelliJ IDEA

IntelliJ offers a ton of refactoring features, and I assume most of these need no introduction. But there are a few lesser-known ones specifically designed for migrations that have saved me a lot of time:

* [Refactor > Migrate Packages and Classes > Create New Migration](https://www.jetbrains.com/help/idea/migrate.html): for simpler migrations where only the package or class name changes.
* [Refactor > Migrate Packages and Classes > Create New OpenRewrite Migration](https://www.jetbrains.com/help/idea/openrewrite.html): to run an existing OpenRewrite [recipe](https://docs.openrewrite.org/recipes) or create and run one of our own.
* [Edit > Find > Replace Structurally](https://www.jetbrains.com/help/idea/structural-search-and-replace.html#structural_replace): for more complex changes/migrations, e.g. when an annotation or it's parameters change. It might take some time to wrap our head around the syntax, the different modifiers and their behavior, but the templates in the sidebar provide examples of the most common use cases to help us get started quickly. Plain-text and regex find-and-replace are not ideal for structural code changes in most cases, because these are not precise enough to limit the scope to only the relevant parts, and don't auto-adjust the imports either.

### GitHub Copilot

I got a GitHub Copilot Business license about halfway through the Spring Boot migration, which was still plenty enough to explore its potential for migrations and help reduce some manual work.

Use cases where it worked best for me:
- Auto-complete repetitive and boring boilerplate code. Some examples:
  - Migrating or refactoring code with some patterns that we can't easily refactor with IntelliJ. When we start making manual changes to the code, Copilot often recognizes the patterns we are using and provides context-aware suggestions for the rest of the code.
  - Mapping DTO/entity fields with the same/similar field names back and forth.
  - Finish the remaining switch-case statements with similar cases.
  - Help write somewhat repetitive code in unit tests. However, this requires extra caution, as there is nothing worse than having false positive tests that give us a false sense of coverage, which can lead to critical bugs getting into production.

Plain LLMs vs GitHub Copilot:
- Plain LLMs usually provide a chat interface in the browser, and it's a bit of a hassle to copy-paste code snippets back and forth, and it has no code context other than the code we explicitly send. The GitHub Copilot plugins provide auto-completions right in the code editor, and integrate the chat into the IDE sidebar, making it more convenient to access.
- On the other hand, the Copilot chat is much slower than e.g. ChatGPT and Claude. The difference is even more striking since the release of GPT-4o and Claude 3.5 Sonnet.
- GitHub Copilot provides some additional features and integrations for IntelliJ, VSCode, Vim and the Terminal.
- The IntelliJ Copilot plugin provides auto-completion based on the code context and open files, comment prompts, and a sidebar chat.
- VSCode provides inline chat, @workspace and @terminal context references and a few other features in addition to the IntelliJ plugin.
- The Vim plugin provides the usual auto-completion. It may have other features too that I haven't explored yet.
- The GitHub Copilot CLI can generate and explain one-liner shell commands.

Problems with GitHub Copilot:
- GitHub Copilot uses the OpenAI Codex under the hood, so it has many of the limitations of ChatGPT and other LLMs. Its suggestions are based on patterns and probabilities, not a deep understanding of the codebase's specific requirements or business logic. The generated code is a hit-and-miss, and while it can save us some time for certain tasks, it can also increase the chance of latent bugs, [quickly degrade the code quality and maintainability](https://www.gitclear.com/coding_on_copilot_data_shows_ais_downward_pressure_on_code_quality) and hinder technical growth if someone blindly accepts its code completions without fully understanding them. It should only complement, not replace, reading the docs, and doing one's due diligence to gain a comprehensive picture of the options available, and deciding what's best for the actual project given the requirements.
- It often generates longer suggestions with only partially relevant content. However, the Copilot plugins provide shortcuts to accept only the next few words or line suggested, rather than accepting the whole thing, which also makes it easier to review each suggestion before accepting it.
- LLMs have a knowledge cutoff, and rarely have up-to-date info about the latest framework and library versions, and even if we explicitly ask it to generate code e.g. for Spring Boot 3, it will happily generate code that only works with some older Spring Boot version, or a completely made up hallucination.

## Migration

### Gradle 6 to 8 migration

Gradle 6 only supports Java up to version 15, so I had to update Gradle first. There were a couple of smaller breaking changes and deprecations between version 7 and 8, and some dependencies required an update to work with the new version.

The [Gradle Compatibility Matrix](https://docs.gradle.org/current/userguide/compatibility.html) provides a lookup table to help find the minimum version required when upgrading Java. 

### Java 8 to 21 migration

The Java upgrade was next in line, as Java 17 is the minimum version required for Spring Boot 3. Java 8 was released over 10 years ago, and while it is still officially supported by some JDK vendors, it is getting difficult to maintain it: many third-party dependencies have stopped supporting it, so upgrading these dependencies to their latest version is no longer an option, leaving us with security holes and annoying bugs. With older Java versions, we miss out on many new performance improvements, security enhancements, and various new features.

Notable new features:
* Text blocks: multi-line strings without escaping and concatenation which makes the text more readable (e.g. a JSON request in tests).
* Enhanced switch statements: switch expressions with type pattern matching and guards produce more concise and easier to grasp conditional logic.
* Pattern matching for the `instanceof` expression: avoids manual type casting which was common after using an `instanceof` check.
* Record classes: simple, immutable data carrier classes that automatically provide constructors, getters, `equals()`, `hashCode()`, and `toString()` methods based on the record's components, reducing the boilerplate code.
* Local variable declaration using the `var` keyword which is inferred at compile-time, so it avoids having to explicitly repeat the same type multiple times without losing the static type info.
* New convenience methods:
  * Collection: `List.of(...)`, `Set.of(...)`, `Map.of(...)`
  * SequencedCollection: `getFirst()`, `getLast()`, `addFirst()`, `addLast()`, `removeFirst()`, `removeLast()`, `reverse()`
  * String: `isBlank()`, `strip()`, `lines()`, `transform(s -> ...)`
  * Stream: `toList()`, `takeWhile(...)`, `dropWhile(...)`, `Predicate.not(...)`, `Predicate.and(...)`, `Predicate.or(...)`
* Javadoc: `@snippet` tag with multi-line code, regex `@highlight`, and referencing code regions using the `@start`/`@end` comments
* `NullPointException`s with more details: previously, NPEs were not very helpful. Now it mentions exactly which field/method call was null.
* Security:
  * TLS 1.3 support
  * ChaCha20 and Poly1305 cryptographic algorithms
  * Key Agreement with Curve25519 and Curve448
* Virtual Threads: lightweight threads that enable concurrent tasks without the overhead of traditional OS threads and promises impressive performance improvements for I/O-bound apps. However, it introduces potential deadlock risks with synchronized blocks and methods that perform a blocking I/O operation and pin the virtual thread to its carrier, and it's hard to ensure that none of the third-party dependencies included into the project do such pinning that could cause a deadlock. This may be fixed in the future by, for example, having virtual threads never pin their carrier threads, but right now it's risky to enable it in production.
* And [many more](https://advancedweb.hu/a-categorized-list-of-all-java-and-jvm-features-since-jdk-8-to-21/).

Notable breaking changes:
* [Removed Tools and Components](https://docs.oracle.com/en/java/javase/21/migrate/removed-tools-and-components.html#GUID-D7936F0D-08A9-411E-AD2F-E14A38DA56A7). E.g:
  * The [Java EE (JAX-WS, JAXB, JSR-250) and CORBA modules were removed in JDK11](http://openjdk.java.net/jeps/320) and need to be explicitly included into the project if used.
  * The [Nashorn JavaScript Engine was removed in JDK15](https://openjdk.java.net/jeps/372).
  * The [native2ascii tool was removed because JDK9+ uses UTF-8 encoding for properties resource bundles by default](https://docs.oracle.com/javase/10/intl/internationalization-enhancements-jdk-9.htm#JSINT-GUID-974CF488-23E8-4963-A322-82006A7A14C7).
* [Removed APIs](https://docs.oracle.com/en/java/javase/21/migrate/removed-apis.html#GUID-8B234260-ED40-4F1F-BCBA-C4BEC05A05D9) E.g: some `Thread` methods, `sun.*` APIs
* [Removed JVM flags](https://chriswhocodes.com/hotspot_option_differences.html). E.g. the [Concurrent Mark Sweep GC was removed in JDK14](https://openjdk.org/jeps/363): `-XX:+UseConcMarkSweepGC`
* [Strong encapsulation of the JDK internal APIs in JDK17](https://openjdk.org/jeps/403), limiting the access to them. This is usually an indicator of a code smell, but the access can be still opened up with the explicit `--add-opens` command-line option if it's really necessary.
  * This broke the HTTP PATCH hack in Jersey and an old RestAssured version, so I temporarily used the `--add-opens` directive until migrated away from Jersey and updated RestAssured.

[OpenRewrite](#openrewrite) provides [recipes](https://docs.openrewrite.org/recipes/java/migrate/upgradetojava21) to automate some of the migration process e.g. to bump the source/compile Java version in the build config, to replace some deprecated APIs, and to easily adopt many new Java features.

I think the trickiest part of such a major Java upgrade is updating the third-party dependencies to at least the minimum version compatible with the new Java version, or the latest one if time permits.
* Updating the dependencies is not always as simple as bumping the version number, but requires finding the release notes for each dependency, looking for breaking changes and deprecations, adapting the code base accordingly and testing the changes.
* Each dependency pulls in its own transitive dependencies and implicitly bumps their version during a dependency update, so we also have to go through the said process for each transitive dependency that we use in the code, which can create a ripple effect.
* Also, some dependencies (even their latest version) may be incompatible with the new Java version and will need to be replaced with an alternative.

Some ideas and tools to help with the analysis and estimation:
* Since Java 17 was the minimum required for Spring Boot 3, I upgraded to that version first, and only upgraded it to Java 21 in a separate task after I had already migrated to Spring Boot which was more critical than the Java 17 to 21 upgrade. There is an overhead to splitting the Java upgrade into multiple steps, but it allows us to break the task into more manageable ones, so it's a trade-off.
* The [jdeprscan](https://docs.oracle.com/en/java/javase/21/docs/specs/man/jdeprscan.html) tool with the target JDK and the `--for-removal` option can find references in the code and dependencies to APIs that have been removed in the target JDK. The [kordamp/jdeprscan-gradle-plugin](https://github.com/kordamp/jdeprscan-gradle-plugin) makes it easier to scan the code-base and the project dependencies using jdeprscan.
* The [jdeps](https://docs.oracle.com/en/java/javase/21/docs/specs/man/jdeps.html) tool with the `--jdk-internals` option can find JDK internal API calls in the code and dependencies, and list the suggested replacements. Similarly, the [kordamp/jdeps-gradle-plugin](https://github.com/kordamp/jdeps-gradle-plugin) makes it more convenient to run the command against the whole project and dependencies. NOTE: jdeps can't warn about code that uses reflection to call the JDK internal APIs as it's checked at runtime.
* The [ben-manes/gradle-versions-plugin](https://github.com/ben-manes/gradle-versions-plugin) can create a report with the outdated (and up-to-date) dependencies, their latest version and a link to the project's home page, so we don't have to look these up manually.
* It's worth spending some time going through the dependencies to see if it supports the new Java version at all or will need to be replaced, and reading the release notes to get an idea of the number and severity of breaking changes and deprecations.
* It's also worth trying to compile the project with the newer Java version and with the dependency versions that are compatible with it, just to see what will break and require additional effort. Since the project won't likely compile at this point (without additional work), we won't see the possible runtime errors yet, but we should estimate some time for those as well.
* There might be an [OpenRewrite recipe](https://docs.openrewrite.org/recipes) that can bump the version number of some dependencies and also adjust the code according to the breaking changes to some extent.

### Log4jv1 to Logback + SL4J migration

The project was using an old log4jv1 and jcan.log version. Log4v2 has some significant changes compared to log4jv1, so migrating to it wouldn't be much easier than migrating to SLF4J + Logback, which I went with instead:
* SLF4J's facade pattern simplifies switching between logging implementations and offering greater flexibility.
* Logback offers a prudent mode which helps to avoid the concurrent service/JVM write issues. For example if multiple microservices/JVMs write to the same log file (e.g. a common audit log file), then some log entries could get lost due concurrent writes unless the prudent mode is enabled. Note that the automatic gzip compression of the logback rotated log files is not compatible with this option, but a fairly simple cronjob can be used an as alternative if necessary.
* Spring Boot also chose SLF4J + Logback as it's default logging framework, and provides 1st class Logback integration.
* The Log4shell vulnerabilities left a bad taste in the mouth when thinking about Log4jv2.

Migration process:
* Replace the jcan.log and log4j Gradle dependencies with the logback and SLF4J.
* Analyze the required changes between the old and new logger class and methods names, and use the [IntelliJ _Migrate Packages and Classes_ and _Replace Structurally_ features](#intellij-idea) to migrate most of the logger code.
  - `ch.nevis.jcan.log.JcanLogger` => `org.slf4j.Logger`
  - `ch.nevis.jcan.log.JcanLoggerFactory` => `org.slf4j.LoggerFactory`
* Migrate the log4j.xml config files to logback xml files.
* Migrate the custom test log appender.

### JUnit 4 to 5 migration

JUnit 5 offers several improvements over JUnit 4, most notably:
- More flexible parameterized tests that work on the method level with multiple argument sources (method source, csv source, etc).
- Additional built-in asserts (e.g. `assertThrows`, `assertInstanceOf`, `assertIterableEquals`, `assertTimeout`) so we don't need to spend time to reinvent the wheel or include additional test libraries.
- Nested test classes to group related tests, and to be able to include them into multiple tests.
- Lambda support making the test code more concise.
- Improved extensibility with the more powerful and flexible extension model instead of the previous runners and rules.

Migration process:
- Use the [OpenRewrite JUnit 4 to JUnit 5 migration recipe](https://docs.openrewrite.org/recipes/java/testing/junit5/junit4to5migration)
- Replace the remaining JUnit 4 deps with JUnit 5.
- Include the JUnit 5 support libs for mockito and greenmail.
- Migrate the JUnit 4 tests to JUnit 5 (OpenRewrite migrates some of these for us):
  - `@RunWith` => `@ExtendWith`
  - `@Rule` => `@RegisterExtension` OR `@ExtendWith` depending on whether we need to reference it in the tests.
  - `@Before` => `@BeforeEach`
  - `@After` => `@AfterEach`
  - `@BeforeClass` => `@BeforeAll`
  - `@AfterClass` => `@AfterAll`
  - `@Ignore` => `@Disabled`.
  - `@Parameterized.Parameters` => `@ParameterizedTest` + `@MethodSource("...")`
  - `TemporaryFolder` => `@TempDir`.
  - Add the `@RuleChain` and `@Order` annotations when necessary.
  - Adapt the custom parameterization code to use `@ParameterizedTest` + `AnnotationBasedArgumentsProvider`.
  - Replace the internal and external runners with extensions.
  - Adapt the parameter order of asserts due to JUnit 5 changes: the message parameter was moved from the 1st to last.
  - Replace the hamcrest library with JUnit 5 built-in features (e.g. `assertThrows` instead of expected exception).
  - Enable parallel unit tests execution after fixing some static context leaking in the tests.

### JUnit assert to AssertJ migration

AssertJ's fluent method chaining allows for more natural language-like assertions. It provides a rich set of assertions, and more detailed and helpful error messages out of the box. With OpenRewrite, the migration from JUnit 5 asserts to AssertJ was quite easy.

Migration process:

- Use the [OpenRewrite Migrate JUnit asserts to AssertJ recipe](https://docs.openrewrite.org/recipes/java/testing/assertj/junittoassertj). This successfully migrated every JUnit 5 assert to AssertJ, and all tests still passed afterwards.
- Use IntelliJ's Reformat files > Only changes uncommited to VCS to reformat the changed lines, most notably to fix lines that are too long.
- Review the changes and fix the remaining formatting issues (e.g. lines that were split by IntelliJ at an awkward position).

### Mockito 1 to 5 migration

As the large version gap also indicates, this was a major Mockito upgrade. At some point between version 1 and 5, Mockito added some strict checks that broke many tests in a non-obvious way so each of these had to be analyzed in detail and manually fixed, which was more tedious than expected. On the other hand, the new Mockito also caught some false-positive tests, and also helps to catch some problems early in future tests, making the effort worthwhile.

Migration steps:

- Use the [OpenRewrite Mockito 5.x upgrade recipe](https://docs.openrewrite.org/recipes/java/testing/mockito/mockito1to5migration) to automate many of the required changes (e.g. change mockito-all dependency to mockito-core, migrate some of the `Matchers` => `ArgumentMatchers` changes).
- MockitoAnnotations.initMocks(this);  method call =>
  - JUnit4: `@Rule public MockitoRule mockitoRule = MockitoJUnit.rule();`
  - JUnit 5: `@ExtendWith(MockitoExtension.class)` class annotation
- Fix the tests that fail due to the change in Mockito's null handling: e.g. `any(...)` => `nullable(...)`
  - Previously, the `Matchers.any(...)` /  `Matchers.anyString(...)` methods also matched null values, but in newer Mockito versions it was split into `ArgumentsMatchers.any(...)` / `ArgumentsMatchers.anyString(...)` and `ArgumentsMatchers.nullable(...)`, and now only the nullable method matches null values.
- Manually fix the tests that broke after the Mockito upgrade due to unnecessary mockings, or use the `lenient()` option in special cases (e.g. in `@BeforeEach` methods if the mock was used by more than 50% of the test methods it didn't make sense to separately do the mock in many of these tests). These changes may catch some false-positive tests where the wrong method was mocked (e.g. same method name, but different parameters), and obsolete mockings which only added unnecessary complexity and increased the test runtimes a bit.

### Java EE6 + Wildfly 10 to Spring Boot 3 migration

We were using an in-house version of Wildfly 10 which was released 8 years ago, and upgrading it to the latest, upstream Wildfly wouldn't be trivial either, so we decided to migrate to Spring Boot 3 instead.

#### Spring Boot Migrator

I did some research to see if there was a project that could help automate some parts of the Spring Boot migration, and found the [spring-projects-experimental/spring-boot-migrator](https://github.com/spring-projects-experimental/spring-boot-migrator) project with some relevant migration recipes: `migrate-statless-ejb`, `migrate-jax-rs` and `migrate-jax-ws`. However, the Spring Boot Migrator (SBM) only works with Maven projects, and we have a Gradle project. But since the SBM tools looked quite promising, I had this crazy idea to try to convert the Gradle project into a Maven project temporarily to be able to run the SBM tool against it.

As I learned, Gradle provides a maven-publish plugin that can generate Maven pom.xml files with the Gradle dependencies, so at first it looked like an easy task, but I didn't find many examples and the documentation is also a bit lacking here, so it was a bit tricky to put together the custom maven-publish task that generated the local pom.xml files with the right attributes for a multi-project repo at the right locations, and it required manually fixing the incorrectly converted dependency types, and generating a root pom.xml with the subprojects/modules too.

Then the project could be built with Maven, so I could finally run the SBM tool against it. At first 3 out of 3 recipes failed with an arcane error, but by excluding some problematic files from the repo, I was able to run at least one of the recipes, and the result was mostly correct, though it basically did the simplest Migration process that are fairly easy to do with IntelliJ too (e.g. replace `@EJB` and `@Inject` annotations with `@Autowired`). So this was a bit of a letdown, but to be fair the SBM tool is in experimental status, it might work better with other projects and may be also improved in the future.

#### Migration process

- Add the Spring Boot Gradle plugin, BOM coordinates and dependencies to the project. The [Spring Initializr](https://start.spring.io) can generate a Gradle / Maven file with the relevant dependencies.
- Remove the explicit dependency versions, which are now managed by the Spring Boot plugin to avoid using incompatible versions.
- Migrate the deprecated and conflicting javax dependencies to jakarta, the most common ones using [OpenRewrite](https://docs.openrewrite.org/recipes/java/migrate/jakarta/jakartaee10). Some had to be completely replaced due to incompatibilities.
- Create the `@SpringBootApplication` annotated Spring Boot starter application classes. One subproject can only have a single Application class, but it is possible to have some conditional logic in the Application class, or to have multiple Runner (e.g. `CommandLineRunner`) classes with conditional annotations, or split the subproject into multiple subprojects if it makes sense.
- Take advantage of Spring Boot's [externalized configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html) to [easily toggle and tweak many of Spring Boot built-in features](https://docs.spring.io/spring-boot/appendix/application-properties/) with application properties, environment variables and CLI flags, customize application behavior without recompiling and redeploying code, and to be able to use environment-specific configurations.
- Use `@Configuration` classes to provide custom `@Bean` definitions and do dynamic configuration of the beans based on conditions, properties, env vars or other factors.
- Configure logging appenders with logback-spring xml files, and the logging levels and various logging parameters with externalized configuration.
- Configure the Spring Boot services in IntelliJ to be able to run directly from the IDE. 
- Migrate the old Java EE, wildfly, glassfish, JAX RS, etc. code + tests to Spring Boot. We can automate some parts of this by analyzing the patterns to be changed and applying them in batch e.g. with IntelliJ's _Migrate Packages and Classes_ and _Structured Replace_ features. The notable patterns I found and applied to the project:
  - Java EE6 => Spring Boot:
    - `@Stateless` / `@LocalBean` / `@Named` => `@Service` / `@Component`
    - `@Inject` / `@EJB` => constructor based Dependency Injection + if there are multiple constructors then add an `@Autowired` annotation to the target constructor that Spring should use for the injection. Constructor DI is recommended over field DI in the production code (and over setter DI, which should be only used for optional dependencies):
      - It helps to avoid runtime errors due to circular dependencies by throwing an error in compile time, so we detect the problem earlier.
      - Makes unit testing easier, as we can directly inject dependencies to the constructor without having to spin up a Spring context (that should be used in integration tests instead). Though Mockito's `@InjectMocks` provides a convenient alternative using reflection, it doesn't report field injection errors and may cause some head scratching.
      - With constructor DI it is possible to mark the fields as final, so the compiler will complain if we have forgotten to initialize a field instead of getting a runtime NPE.
      - The cons of constructor injection is the more verbose code, but with IntelliJ it's easy to generate the constructor and add new fields to it, and we can also use codegen tools like Lombok to reduce the boilerplate code (though it has it's own problems).
    - Replace the custom CDI implementation with Spring Boot components + injections + fix circular dependencies (project-specific).
    - Use `@Primary` / `@Qualifier` / `@ConditionalOnProperty` / etc. on services with multiple implementations
    - `@Asynchronous` => `@Async` + `AsyncConfig` with `@EnableAsync`
    - `@Schedule(hour = ..., minute = ..., persistent = false)` => `@Scheduled(cron = ...)` + `SchedulingConfig` with `@EnableScheduling`
  - JAX RS => Spring Boot / Spring MVC:
    - `ExceptionMapper` => `@RestControllerAdvice` class that extends `ResponseEntityExceptionHandler` +` @ExceptionHandler(...)` methods
    - `Response` -> `ResponseEntity`
    - `Response.Status` => `HttpStatus`
    - `new WebApplicationException(STATUS)` => `new ResponseStatusException(STATUS)`
    - `new InternalServerErrorException(MESSAGE)` => `new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, MESSAGE)`
    - `new BadRequestException(MESSAGE)` => `new ResponseStatusException(HttpStatus.BAD_REQUEST, MESSAGE)`
    - `new NotFoundException(MESSAGE)` => `new ResponseStatusException(HttpStatus.NOT_FOUND, MESSAGE)`
    - `new NotAuthorizedException(MESSAGE)` => `new ResponseStatusException(HttpStatus.FORBIDDEN, MESSAGE)`  
      (the terminology is a bit confusing here, but `NotAuthorizedException` used to return `Response.Status.FORBIDDEN`)
    - `jakarta.ws.rs.core.MediaType` => `org.springframework.http.MediaType`
    - `MediaType.*` (except `MediaType.*_TYPE`) => `MediaType.*_VALUE`
    - `MediaType.*_TYPE` => `MediaType.*`
    - `@RequestScoped` => `@RestController` for REST controllers, otherwise `@RequestScope`
    - add `@RestController` to the REST interfaces too (if there are any)
    - REST controller class/interface annotations:  
      `@Path(...) @Produces({ MediaType.APPLICATION_JSON }) @Consumes({ MediaType.APPLICATION_JSON })` => `@RestController @RequestMapping(value = ..., produces = {MediaType.APPLICATION_JSON_VALUE})`
      - only specify the `consumes = {MediaType.APPLICATION_JSON_VALUE}` for the method level `@RequestMapping`, as the class level annotation would cause a problem with the `@GetMappings`
    - `@GET` => `@GetMapping`
    - `@POST` => `@PostMapping`
    - `@PUT` => `@PutMapping`
    - `@PATCH` => `@PatchMapping`
    - `@DELETE` => `@DeleteMapping`
    - merge `@Path`, `@Produces` and `@Consumes` with `@*Mapping` annotations
    - `@QueryParam` => `@RequestParam` + add `required=false` options to the `@RequestParam` annotations where necessary which was the default with JAX-RS, but not anymore
    - `@FormParam` => `@RequestParam`
    - `@PathParam` => `@PathVariable`
    - merge `@RequestParam` with `@DefaultValue` annotations
    - `@BeanParam` => remove annotation
    - add `@RequestBody` to `@RequestMapping` method input model/DTOs
    - `ClientBuilder.newBuilder` => `RestClient.builder`
    - `Invocation.Builder` => `restClient`
    - `Response.Status.*` => `HttpStatus.*`
    - `Response` => `ResponseEntity`
  - Migrate the JAX-RS, Jersey and Apache HttpClient 4 REST client code to Spring Boot's RestClient + Apache HttpClient 5. Given the number of REST clients and messy code, this required a lot of manual code and automated test changes.
    - Keep in mind the double encoded URI issue that can occur if the previous REST client didn't encode the URI, so previously it had to be pre-encoded, but Spring Boot's RestClient now automatically encodes the URI, causing it to be encoded twice. This is true for both the base `uri(...)` and the `pathSegment(...)` (but not for `path(...)`).
    - A common error we can run into sporadically: `org.apache.hc.core5.http.NoHttpResponseException: localhost:8080 failed to respond`. One solution is to build a custom RequestFactory + HttpClient configured to proactively evict expired + idle HTTP client connections.
  - Merge the separate Data Rest component into the core project, which was temporarily used for a previous data layer migration (project-specific).
  - Migrate the remaining plain JDBC queries to Spring Data.
  - Migrate the Java EE scheduled tasks to Spring.
  - Migrate the web/application server configurations (e.g. web.xml, standalone.xml) to Spring.
  - Set up REST exception handling and custom error response format.
    - The custom REST error response format and the exception propagation for it was trickier than expected. This was required for backward compatibility with the frontend and REST clients, but for new Spring Boot project I would keep using the default REST error response format, because it's a PITA to set it up correctly to cover all cases. Most of the exceptions can be handled with a `@RestControllerAdvice` + `@ExceptionHandler` methods, but we need to configure an accessDeniedHandler in Spring Security to be able to handle `AccessDeniedException`s, we need to handle the client exceptions too if we have a `@ExceptionHandler(Exception.class)` to avoid spamming the log, and we can't handle some Spring MVC and Spring Security / Unauthorized exceptions there, but need to configure a custom `errorAttributes` bean for those.
  - Migrate the async executor used for non-critical tasks to avoid blocking requests.
  - Configure HTTP access logging for auditing.
  - Set up on-demand request logging for debugging.
  - Configure health check, monitoring and management with actuator. Migrate the prometheus metrics server from jmx_prometheus_javaagent to actuator + the latest micrometer.
    - Exclude sensitive info from the monitoring, enable only the necessary endpoints by default, and ensure that management endpoints are disabled and accessible only by admins and only in certain environments even if enabled at some point e.g. for debugging.
  - Serve the static frontend resources with the web server. Spring Boot can serve the frontend resources without having to pack it into a war or jar file, making the build and deployment easier and the resource serving a bit faster.
  - Set up HTTPS / SSL bundle with hot-reload. Spring Boot 3 enables TLSv1.3 and TLSv1.2 by default.
  - Enable HTTP/2 over TLS. HTTP/2 offers many advantages over HTTP/1.1 which can massively reduce load times, most notably:
    - Multiplexing: the browser can fetch multiple assets parallel over a single TCP connection.
    - Stream prioritization: prioritizes important resources (e.g. css and js) before others.
    - Binary protocol: more efficient than the previous text-based.
    - Header compression: further reduces bandwidth.
  - Spring Security:
    - Spring Security recently underwent a major overhaul, so there's a lot of outdated info and deprecated code on the web, so the best way to get accurate information is by consulting the latest [Spring Security refdocs](https://docs.spring.io/spring-security/reference/index.html) and [javadoc](https://docs.spring.io/spring-security/site/docs/current/api/index.html). Also read the [preparation notes for the next Spring Security version](https://docs.spring.io/spring-security/reference/migration-7/index.html) to avoid using deprecated stuff.
    - Implement the authentication provider.
    - Enforce authentication and authorization rules for the different endpoints.
    - Configure additional security features. A few examples:
      - CSRF protection is an important security measure to prevent unauthorized actions from being performed on a user's behalf who is logged in to the application in the browser.
        - If HTTP compression is enabled either in the application or in the proxy, BREACH attacks can exploit it and extract the CSRF tokens unless we apply some techniques to mitigate these attacks e.g. by XORing the CSRF token with some secure random bytes on each request.
      - `Same-origin` referrer-policy header: there is a convenience method to enable it in the `SecurityFilterChain`.
      - `SameSite=strict` cookie: can be enabled with application properties: `server.servlet.session.cookie.same-site: strict`
  - Implement short-lived caching of current user details to improve the performance of parallel requests.
  - Configure HTTP caching of static resources to improve the web UI performance.
  - Enable graceful shutdown for the web servers. Stop processing new requests on shutdown, but wait for existing requests to complete until the configured timeout expires.
    - The stop_grace_period of the docker containers should be higher than the graceful shutdown period of the web server.
  - Configure Swagger for auto-generated OpenAPI REST API docs. The [springdoc-openapi](https://springdoc.org/) dependency makes it fairly easy to set up, and configure it with application properties.
    - If the server is behind a proxy, then the `server.forward-headers-strategy: framework` might be required, otherwise Swagger will send the requests directly to the server and fail with an unauthenticated error.
    - If CSRF protection is enabled for the app, then we also need to enable the `springdoc.swagger-ui.csrf.enabled: true` property in Swagger.
  - Remove the obsolete dependencies: jakarta/javax.\*, jboss, glassfish, jersey, etc.
  - Upgrade all remaining third-party dependencies to the latest version. This helped to reduce the number of vulnerabilities reported by xray to zero (at least for a while, until new ones pop up), and also to make the periodic dependency upgrades easier.
  - Adapt and fix the unit, integration and e2e tests, add tests for uncovered cases and fix the caught regressions.
  - Fix some old bugs and critical Sonar findings that come to the surface during the migration.
  - Optimize runtime dependencies to reduce the size of the docker images and speed up the service startup times.
  - Adjust the build and deployment scripts and Dockerfiles to use Spring Boot instead of Wildfly.
    - Spring Boot provides a multi-layer index for more optimal docker images. Third-party project dependencies tend to change less frequently than first party source code, so by breaking the docker COPY step into multiple steps, we can likely reuse some layers in the next deployments, speeding up the docker image build and pull.
    - Configure Spring Boot to automatically create PID and port files for background services so that we can reliably check their status and stop/restart them.
  - Extensive technical and manual testing to catch and fix the remaining bugs before the go-live.

## Conclusion

There is no clear, established path for migrating enterprise applications away from legacy technologies, each system is somewhat unique and faces its own set of challenges during such a migration. Big-bang migrations shouldn't take too long either, otherwise we will run into more and more merge conflicts with new features, or have to implement them twice for both the old and the migrated system. That's why it's crucial to do a detailed analysis and planning prior to the migration to see what parts we can automate, and to get a reasonable estimate without too many surprises. But it's quite hard to think about every required migration step in advance and to see the potential challenges ahead. I hope this comprehensive overview will help other teams anticipate the potential obstacles and plan and execute their migrations more effectively, ensuring a smoother transition and minimizing unexpected setbacks.