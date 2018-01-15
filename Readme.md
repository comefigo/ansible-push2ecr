# 概要

AnsibleでAmazon Elastic Container Registry(ECR)にDocker ImageをPushする方法とハマリポイントを残したいと思います。

# 手順

下記の手順においては、実行環境にあらかじめAnsibleとDockerが導入されている前提とします

IAMポリシー作成と付与 → Dockerビルド → イメージPushの流れです


## サンプルコード

以下の説明こちらのサンプルコードをベースに説明しています

https://github.com/comefigo/ansible-push2ecr

### hosts

```ini:hosts
[local]
localhost ansible_connection=local

[local:vars]
region=ap-northeast-1
key_id=xxxxxxxxxxxxxx
access_key=xxxxxxxxxxxxxxx
image_name=hogehoge/fugafuga
image_version=latest
```

### playbook

```yaml:push_image.yml
---
- name: push docker image to AWS ECR Sample
  hosts: local
  tasks:
    - name: make aws directory
      file:
        dest: ~/.aws
        state: directory
        mode: u=rwx,g=,o=

    - name: copy aws config
      template:
        src: aws/config
        dest: ~/.aws/config
        mode: u=rw,g=,o=

    - name: copy aws credentials
      template:
        src: aws/credentials
        dest: ~/.aws/credentials
        mode: u=rw,g=,o=

    - name: install docker-py for build docker
      pip:
        name: boto3
        state: present

    - name: build docker image
      docker_image: 
        path: ./
        name: "{{ image_name }}"
        tag: "{{ image_version }}"

    - name: docker login (must `--no-include-email`)
      shell: "$(aws ecr get-login --region {{ region }} --no-include-email)"
      args:
        executable: /bin/bash

    - name: install boto3
      pip:
        name: boto3
        state: present

    - name: create repository
      ecs_ecr:
        name: "{{ image_name }}"
        aws_access_key: "{{ key_id }}"
        aws_secret_key: "{{ access_key }}"
        region: "{{ region }}"
      register: ecr_repo

    - name: add tag
      docker_image:
        name: "{{ image_name }}:{{ image_version }}"
        repository: "{{ ecr_repo.repository.repositoryUri }}"
        tag: "{{ ecr_repo.repository.repositoryUri }}:{{ image_version }}"

    - name: push image to ecr
      docker_image:
        name: "{{ ecr_repo.repository.repositoryUri }}:{{ image_version }}"
        push: yes
```

## 1. IAMポリシーの作成と付与

ECRを操作するための権限（ポリシー）を作成します  
以下のJSONデータをポリシー作成のJSONタブに貼り付けるか、作成画面で項目を選択してください

![FireShot Capture 1 - IAM Management Console_ - https___console.aws.amazon.com_iam_.png](https://qiita-image-store.s3.amazonaws.com/0/30522/efc3258c-880e-4d52-9e0e-adca83d12e7c.png)


ひとまずすべて許可になっていますが、  
必要に応じて`Action`や`Resource`を絞ってください

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "ecr:*",
            "Resource": "arn:aws:ecr:*:*:repository/*"
        }
    ]
}
```

操作できるリポジトリ、リージョン、アカウントIDなどを制限したい場合は、  
以下の`"Resource": "arn:aws:ecr:ap-northeast-1:xxxxxxxx:repository/yyyyyyyyyy"`という風にしてください
![iam2.png](https://qiita-image-store.s3.amazonaws.com/0/30522/36a16784-fbf6-53d7-1a68-abf8313497f1.png)

ポリシーの作成後に対象のIAMユーザに付与してください

**※付与したユーザのアクセスキーとシークレットキーを`hosts`の`key_id`と`access_key`にそれぞれ追加してください**


## 2. AnsibleでDockerイメージのビルド

docker_imageモジュールを用いてイメージのビルドを行います

```yaml:push_image.yml
~~ 前略 ~~

- name: build docker image
  docker_image: 
    path: ./
    name: "{{ image_name }}"
    tag: "{{ image_version }}"
```

## 3. Docker loginする(ECR経由)

`--no-include-email`を入れないと`unknown shorthand flag: 'e' in -e`でエラーになります(**ハマリポイント**)  
get-loginで取得される`docker login xxxxxx`に存在しないパラメータ(`-e`)が含まれているため

```yaml:push_image.yml
~~ 前略 ~~

- name: docker login (must `--no-include-email`)
  shell: "$(aws ecr get-login --region {{ region }} --no-include-email)"
```

もし、ansible.cfgで`executable=/bin/bash -l`を設定している場合は、  
argsで`/bin/bash`を追加してください(**ハマリポイント**)

```yaml:push_image.yml
- name: docker login (must `--no-include-email`)
  shell: "$(aws ecr get-login --region {{ region }} --no-include-email)"
  args:
    executable: /bin/bash
```

## 4. ECSにリポジトリを作成

ecs_ecrモジュールはaws apiを用いるため、boto3をインストールします

```yaml:push_image.yml
~~ 前略 ~~

- name: install boto3
  pip:
    name: boto3
    state: present

- name: create repository
  ecs_ecr:
    name: "{{ image_name }}"
    aws_access_key: "{{ key_id }}"
    aws_secret_key: "{{ access_key }}"
    region: "{{ region }}"
  register: ecr_repo
```

## 5. ECR用にタグ付け

ECRの「プッシュコマンドの表示」で示されているようにタグ付け(手順4)をしていきます  
前述のregister(ecr_repo)に格納されている`repositoryUri`を用います

![push_command.png](https://qiita-image-store.s3.amazonaws.com/0/30522/628bc839-f8d3-af4b-5a19-89f691903e3a.png)

```yaml:push_image.yml
~~ 前略 ~~

- name: add tag
  docker_image:
    name: "{{ image_name }}:{{ image_version }}"
    repository: "{{ ecr_repo.repository.repositoryUri }}"
    tag: "{{ ecr_repo.repository.repositoryUri }}:{{ image_version }}"
```

## 6. イメージのpush

タグ付けしたイメージをプッシュする

```yaml:push_image.yml
~~ 前略 ~~

- name: push image to ecr
  docker_image:
    name: "{{ ecr_repo.repository.repositoryUri }}:{{ image_version }}"
    push: yes
```

