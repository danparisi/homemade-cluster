# Go Native

My journey to the native image build & deployment was not that straightforward as I thought,
it took some time to really understand the process and adjust all the components in order to have fully running services
in native images.

This was probably not only about me, for example see this comment from
a [nice reddit post](https://www.reddit.com/r/java/comments/10cv886/personal_experiences_with_native_graalvm_images/):
> I do not even think we are in the alpha stage. \
> For example, for 2 days I am fighting with a simple microservice using JPA, MySQL, some transactions and without
> success.
>
> Fixed at least 4 bugs, and now I gave up.
>
> I cannot imagine what problems can arise in mid-size projects.

## Preface

Let's do a very small recap about Java compilation before digging into native image issues I faced.

We are used to compile java code in bytecode (not machine code yet), to be later interpret by a running JVM.
Additionally, the JVM figures out which chunks of your code are executed more often - _hot paths_ - and will compile
their related bytecode to machine code.

By such runtime information, static code analysis, etc. the **JIT** - **J**ust **I**n **T**ime - compiler is able to
create very optimized machine code, and that's why Java applications running on regular JVMs go faster after some
warm-up time.

So what is instead the **AOT** - **A**head **O**f **T**ime - compiler?

The _AOT_ compiler will do most of the job at compile time (as opposed to _JIT_) and almost none at run time,
and will create a native executable. It means no bytecode interpretation / compilation will be required at runtime.
This also means that the AOT needs to do static code analysis with closed-world assumptions,
meaning that it must know at build time all the classes that can be reachable at runtime in order to include them in the
binary. So everything that is loaded dynamically, like reflection, JNI, proxies, etc. won't be part of the compilation
result and therefore will lead to runtime issues.
Additionally, compared to regular compilation, AOT is much more expensive in terms of resources and time.

So why should I compile native images instead of going for regular java application running on JVM ?

First of all, because of **start-up time**. Spring boot native images are up and running in few seconds or less, instead
of 30-60+ seconds. And this is crucial when we want to **autoscale** our services. New instances should be quickly up to
get requests in case of peeks. This is quite difficult in case of regular spring boot application, as longer startup
time may result in _unhealthy running instances_ because of the high volume traffic. Moreover, having the chance to very
quickly raise up new instances let you keep the number or running replicas very low if not many requests are there and
therefore save money. Last but not least when we are in the cost topic, Spring AOT compiled application should have a
smaller memory footprint compared to regular ones.

## Pain points

Here are the main pain points I needed to face, for some of them it took a while to understand the root of the issue:

* [Write and maintain GraalVM hints](#write-and-maintain-graalvm-hints)
* [Resource and time consuming build](#resource-and-time-consuming-build)
* [Consul config refresh not supported](#consul-config-refresh-not-supported)
* [Gateway not migrated to native image](#gateway-not-migrated-to-native-image)
* [Spring cloud kubernetes not supported](#spring-cloud-kubernetes-not-supported)
* [Feign clients require server list in property files](#feign-clients-require-server-list-in-property-files)
* [Janino, used for conditions inside logback.xml, not supported](#janino-used-for-conditions-inside-logbackxml-not-supported)

## Write and maintain GraalVM hints

As explained above, reflection won't work out of box when you AOT compile native images. In order to keep it working,
you need to provide to _GrallVM_ a list of all the classes meant to be instantiated by reflection. You can do that by
creating a _reflect-config.json_ in your classpath. To be more specific,
my [SpringConfigImportEnvironmentPostProcessor](https://github.com/danparisi/dan-service-tech-starter/blob/main/src/main/java/com/danservice/techstarter/processor/SpringConfigImportEnvironmentPostProcessor.java)
didn't work while migrating to native images because it makes use of jackson to read
my [SpringProperties](https://github.com/danparisi/dan-service-tech-starter/blob/main/src/main/java/com/danservice/techstarter/SpringProperties.java)
that internally do that by reflection, therefore I needed to list all my custom properties
classes [here](https://github.com/danparisi/dan-service-tech-starter/blob/main/src/main/resources/META-INF/native-image/reflect-config.json).

Another similar issue I needed to face was related to _Resilience4j retry_ configuration:

```
resilience4j:
  ...
  retry:
    configs:
      default:
        ...
        retryExceptions:
          - java.net.ConnectException
          - java.net.UnknownHostException
          ...
```

Basically also here the library _Resilience4j_ is using reflection in order to instantiate the exception classes from
the list above. This was leading to runtime exceptions like the following:

```
Failed to bind properties under 'resilience4j.retry.configs.default.retry-exceptions[2]' to java.lang.Class<java.lang.Throwable>:

    Property: resilience4j.retry.configs.default.retry-exceptions[2]
    Value: "java.net.SocketTimeoutException"
    Origin: class path resource [application.yml] - 98:13
    Reason: failed to convert java.lang.String to java.lang.Class<java.lang.Throwable> (caused by java.lang.ClassNotFoundException: java.net.SocketTimeoutException)

```

So, I needed to list all the exception
classes [here](https://github.com/danparisi/dan-service-tech-starter/blob/main/src/main/resources/META-INF/native-image/reflect-config.json).

:information_source: This requirement was not documented anywhere, so I also asked the community to enhance the
documentation as you can
see [here](https://github.com/resilience4j/resilience4j/issues/2184).

Last but not least, I also need to provide reflection hints about all the classes supposed to be serialized by Jackson
(see the
docs [here](https://docs.spring.io/spring-boot/reference/packaging/native-image/advanced-topics.html#packaging.native-image.advanced.custom-hints))
because used as kafka message bodies. I did it programmatically, as you can
see [here](https://github.com/danparisi/dan-pretrade-service/blob/main/src/main/java/com/danservice/pretrade/Application.java#L15)
by using the
_RegisterReflectionForBinding(...)_ annotation. Here is a small example:

```
@SpringBootApplication
...
@RegisterReflectionForBinding(KafkaClientOrderDTO.class)
public class Application {
```

## Resource and time consuming build

Title is quite self explaining, AOT compilation for native image is very expensive for both time and resources.
Reason is that AOT compilation requires to analyze the whole code in order to create the binary as described above.

I'm running the compilation inside a Jenkins agent POD, the GraalVM _native-maven-plugin_ by default is trying to
consume all the resources available in the system. I was expecting the resource calculation was based on POD limits but
for some reason it's instead getting my host machine capacity and taking all of it for the compilation. Few times it
leaded to laptop freeze and restart required. I think it happens because of some _microk8s_ abstraction layer bug, in
theory it should not be able to get node information but it does. Or maybe I'm missing something. I raised the question
to the _microk8s_ community on [GitHUB](https://github.com/canonical/microk8s/issues/4542) but didn't get any answer.

The workaround I adopted was to manually set the maximum resource allowed to be consumed by the compiler directly in the
_spring-boot-maven-plugin_ configuration:

```
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <configuration>
                    ...
                    <image>
                        <env>
                            <BP_NATIVE_IMAGE_BUILD_ARGUMENTS>-J-Xmx8g --parallelism=4</BP_NATIVE_IMAGE_BUILD_ARGUMENTS>
                        </env>
```

:warning: Still would be hard to handle 2 or more simultaneous AOT compilation build within my 32gb host machine.

## Consul config refresh not supported

Configuration refresh at runtime, for example from Consul, is currently not supported in native images and therefore I
needed to disable it in my java technical library _application.yml_:

```
spring:
  cloud:
    refresh:
      enabled: false
    openfeign:
      client:
        refresh-enabled: false
```

:information_source: This is such a pity in my opinion as letting the configuration to be updated at runtime without
requiring any restart is a quite powerful feature. Hopefully it will be supported in the near future.

## Gateway not migrated to native image

After struggling a bit, I decided to keep my gateway service on regular JVM (no native image then) because:

* Probably auto scaling can be avoided here (it's a reactive service with quite good throughput by itself), or can be
  tuned to work even though the startup is not that fast (maybe lower CPU threshold to get a new replica)
* As stated above, config refresh would not be supported, but this is a feature I really want to have here. Mainly in
  order to modify routes without restarting the services
* The gateway service usually is not updated that often and therefore supposed to be running for long time without any
  restart, therefore JIT compilation fits well and there are not that many benefits to go native
* AOT support would need to list ALL the load balanced services in the _application.yml_ as stated
  [here](https://docs.spring.io/spring-cloud-gateway/reference/spring-cloud-gateway/aot-and-native-image-support.html).
  It would be quite verbose and boring to maintain for the gateway use case.
* My custom kubernetes discovery client implementation would not work out of the box because route service IDs don't
  always match with service instance IDs (for example the _consul-ui_ route doesn't match with the service name
  _consul_)

## Spring cloud kubernetes not supported

Unlikely, _Spring cloud kubernetes_ is not yet supported for AOT and native images as
stated [here](https://docs.spring.io/spring-cloud-kubernetes/reference/index.html#aot-and-native-image-support).
When I discovered it, it was such a pain as my service to service communication and load balancing was fully relying on
it. Therefore, I needed to implement my own one. In the end it was not complicated, I only had few kubernetes client
java API version conflicts with spring dependencies and some other minor issue, but after fixing everything it looks
working quite well. If curious, you can see the
implementation [here](https://github.com/danparisi/dan-service-tech-starter/blob/main/src/main/java/com/danservice/techstarter/autoconfigure/MyBaseKubernetesDiscoveryClient.java).

:warning: Even if it works as a charme, it's not a production ready implementation.

## Feign clients require server list in property files

Feign clients are load balanced and - as
stated [here](https://docs.spring.io/spring-cloud-commons/docs/current/reference/html/#aot-and-native-image-support) - I
needed to provide a list of the server for each repository, for example:

```
spring:
  cloud:
    loadbalancer:
      eager-load:
        clients: service-1, service-2, etc.
```

This is a bit boring to be maintained but not really a big deal. A real example can be
found [here](https://github.com/danparisi/dan-pretrade-service/blob/main/src/main/resources/config/application.yml).

:information_source: Additional _Spring Boot Openfeign_ AOT and Native Image Support information can be
found [here](https://docs.spring.io/spring-cloud-openfeign/docs/current/reference/html/#aot-and-native-image-support).

## Janino, used for conditions inside logback.xml, not supported

Not really a big deal here, I was using the _Janino_ dependency in order to conditionally exclude streaming logs against
kafka when the spring boot application is not running on kubernetes. Mainly to avoid long startup time during
integration test executions. To reach the same result I needed to add a copy of _logback-spring.xml_ in each service's
_test/resources_ folder as you can
see [here](https://github.com/danparisi/dan-service-tech-starter/blob/main/src/test/resources/logback-spring.xml). This
is more verbose (as you need to copy/pasta the same file into each service repository) but not a big deal. The prop is
that I got rid of Janino dependency from the platform library POM, and the fewer dependencies I've in the POM the most
happy I am.

---

## Issues list

Here are all the issues I needed to create or to deal with in my journey to native images:

* https://github.com/qos-ch/logback/issues/757
* https://github.com/canonical/microk8s/issues/4542
* https://github.com/resilience4j/resilience4j/issues/2184
* https://github.com/spring-projects/spring-boot/issues/40149
* https://github.com/spring-projects/spring-boot/issues/40429
* https://github.com/spring-projects/spring-boot/issues/33758
* https://github.com/kubernetes-sigs/prometheus-adapter/issues/590
* https://github.com/spring-cloud/spring-cloud-kubernetes/issues/1350
* https://stackoverflow.com/questions/78611781/spring-boot-native-image-how-to-remote-debug
