# CarpinchoMQ

<div id="top"></div>

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://cdn-animation.artstation.com/p/video_sources/000/080/066/capyyyy.mp4">
    <img src="/logo.jpg" alt="Logo" width="80" height="80">
  </a>

  <h3 align="center">CarpinchoMQ</h3>

  <p align="center">
    Cola de mensajes Distribuida
    <br />
    <a href="https://docs.google.com/presentation/d/1HgivT7YPVJQN71RMrjoUlzzz0X-XaXinuUV8ZzbuzTk/edit"><strong>Arquitectura</strong></a>
    <br />
    <br />
    <a href="https://github.com/TP-IASC/CarpinchoMQ/issues">Reportar Bug</a>
    ·
    <a href="https://github.com/TP-IASC/CarpinchoMQ/issues">Solicituar un Feature</a>
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Tabla de Contenido</summary>
  <ol>
    <li>
      <a href="#acerca-del-proyecto">Sobre el Proyecto</a>
      <ul>
        <li><a href="#tecnologias">Tecnologias</a></li>
      </ul>
    </li>
    <li>
      <a href="#empezando">Empezando</a>
      <ul>
        <li><a href="#prerequisites">Prerequisitos</a></li>
        <li><a href="#usage">Uso</a></li>
      </ul>
    </li>
    <li><a href="#contributing">Contribuciones</a></li>
    <li><a href="#licencia">Licencia</a></li>
    <li><a href="#contact">Contactos</a></li>
    <li><a href="#acknowledgments">Fuentes</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## Acerca del Proyecto

Carpincho MQ surge de la necesidad de reflejar los conceptos estudiados en la materia Arquitecturas Concurrentes de la Facultad Tecnologica Nacional Argentina (UTN)

Para ello se desarrollo una solucion software de administracion de colas de mensajes distribuida, con dos modos de trabajo:

* Cola de trabajo: el mensaje sera entregado unicamente a uno de los consumidores disponibles suscriptos a la cola (elegido de forma round-robin).
* Publicar-suscribir: El mensaje sera entregado a todos los consumidores disponibles suscriptos

Por otro lado, los receptores de la cola de mensajes podrán optar por dos modalidades de consumo:

* Consumo no Transaccional:
  CarpinchoMQ coinsidera que fue un consumo exitoso del mensaje sin esperar la confirmacion por parte del receptor que lo proceso completo (se envia el ACK al principio del procesamiento del mensaje)

* Consumo transaccional:
  CarpinchoMQ coinsidera que fue un consumo exitoso del mensaje tras la confirmacion por parte del receptor que lo proceso completo (se envia el ACK luego de haber completado el procesamiento del mensaje).

Si el receptor no envia la confirmacion en determinado tiempo, por timeout se coinsidera que el consumo fallo.

  En este caso Carpincho hara lo siguiente:
* Si Carpi trabaja en modo "cola de trabajo", se lo enviara a otro consumidor.
* Si Carpi trabaja en modo "Publicar-Suscribir", se reencola hasta que el consumidor lo adquiera.

<p align="right">(<a href="#top">back to top</a>)</p>



### Tecnologias

CarpinchoMQ nacio gracias a:


* [elixir.ex](https://elixir-lang.org/)
* [horde](https://hexdocs.pm/horde/getting_started.html)

* [Node.js](https://nodejs.org/es/)
* [React.js](https://es.reactjs.org/)

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Empezando

### Prerequisitos

Debemos tener instalado:
* Visual Studio Code (recomendacion para levantar el proyecto).
* [Elixir](https://elixir-lang.org/install.html) 
* Horde, en caso de error al levantar el proyecto usar el comando:
```sh
mix deps.get
 ```

<!-- USAGE EXAMPLES -->
## Uso

Para utilizar CarpinchoMQ debes levantar lineas de comando.
A continuacion te pasamos los comandos:

* Levantar un nodo nuevo en una consola (para tirarlo abajo Ctrl+C): 
 ```sh
   iex --sname <nombre_nodo> -S mix 
   ``` 
* Crear una cola nueva: 
```sh
Producer.new_queue <nombre_cola>
  ``` 
* Pushear un mensaje a la cola: 
```sh
Producer.push_message <nombre_cola>,<mensaje>
  ``` 
* Crear un Consumidor: 
```sh
{:ok, pid} = Consumer.start_link
 ``` 
* Suscribir un consumidor a una cola: 
```sh
Consumer.subscribe <nombre_cola>,<pid_consumidor>
 ``` 
* Desuscribir un consumidor de una cola: 
```sh
Consumer.unsubscribe <nombre_cola>,<pid_consumidor>
 ``` 
* Ver el estado de una cola: 
```sh
Queue.state <nombre_cola>
 ``` 
* Ver si una cola está viva: 
```sh
Queue.alive? <nombre_cola>
 ``` 

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

Ayudanos a crecer con tu codigo siguiendo los siguientes pasos

1. Fork del proyecto
2. Creacion de tu Branch (`git checkout -b feature/AmazingFeature`)
3. Commit de tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a tu branch (`git push origin feature/AmazingFeature`)
5. Abrir Pull Request

<p align="right">(<a href="#top">back to top</a>)</p>



<!-- LICENSE -->
## Licencia

Distributed under the UTN License. See `LICENSE.txt` for more information.

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- ACKNOWLEDGMENTS -->
## Agradecimientos

Agradecemos a los profesores y ayudantes de la materia "Implementación de Arquitecturas de Software Concurrentes"
* Ernesto Bossi
* Agustin
* Erwin Debusschere
* NicoR

<p align="right">(<a href="#top">back to top</a>)</p>
