# Publicar Suscribir

* Levanto 2 nodos (`iex --sname <nombre_nodo> -S mix`)
* En el nodo 1 creo una cola con el modo publicar suscribir (`Producer.new_queue :cola1, 23, :publish_subscribe`)
* En el nodo 2 creo 2 consumidores (`{:ok, pid} = Consumer.start_link`) y los suscribo a la cola 1 (`Consumer.subscribe :cola1, pid`)
* Ahora pusheo un mensaje (`Producer.push_message :cola1, "Holaa"`) (y puedo poner un sleep de unos 20 segundos en Consumer en el handle cast que recibe el mensaje, para que tarde un poco en contestar con el ack y pueda chequear algunas cosas)
* Mientras esperamos los acks, vemos el estado de la cola (`Queue.state :cola1`), aca podremos ver los suscriptores de la cola, el mensaje almacenado en la cola, y que para ese mensaje tenemos 2 consumidores que todavia no respondieron con ack
* En cuanto lleguen los 2 acks, se va a eliminar el mensaje de la cola, por lo que si volvemos a consultar el estado de la cola este no tendrá elementos. (si un consumidor no respondiera con ack, el mensaje nunca se borraria de la cola)

# Round robin
